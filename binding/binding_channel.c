#include "binding_common.h"
#include "binding_channel.h"
#include <stdio.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <liburing.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/time.h>
#include "fiber_channel.h"
#include "fiber.h"
#include "binding_balancer.h"
#include "binding_message.h"
#include "dart/dart_api.h"

static volatile uint32_t next_id = 0;

struct transport_channel_context
{
  uint32_t id;
  struct fiber_channel *channel;
  struct transport_balancer *balancer;

  struct io_uring_buf_ring *read_buffer_ring;
  size_t read_buffers_count;
  uint32_t read_buffer_shift;
  unsigned char *read_buffer_base;

  uint32_t buffer_size;

  struct mempool write_buffers;
};

static inline void dart_post_pointer(void *pointer, Dart_Port port)
{
  Dart_CObject dart_object;
  dart_object.type = Dart_CObject_kInt64;
  dart_object.value.as_int64 = (int64_t)pointer;
  Dart_PostCObject(port, &dart_object);
}

static inline unsigned char *transport_channel_get_buffer(struct transport_channel_context *context, int id)
{
  return context->read_buffer_base + (id << context->read_buffer_shift);
}

static inline void transport_channel_setup_buffers(transport_channel_configuration_t *configuration, struct transport_channel *channel, struct transport_channel_context *context)
{

  context->read_buffer_shift = configuration->buffer_shift;
  context->read_buffers_count = configuration->buffers_count;
  context->buffer_size = 1U << configuration->buffer_shift;
  size_t buffer_ring_size = (sizeof(struct io_uring_buf) + context->buffer_size) * configuration->buffers_count;
  void *buffer_memory = mmap(NULL, buffer_ring_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (buffer_memory == MAP_FAILED)
  {
    log_error("allocate buffers failed");
    return;
  }
  context->read_buffer_ring = (struct io_uring_buf_ring *)buffer_memory;
  context->read_buffer_base = (unsigned char *)context->read_buffer_ring + sizeof(struct io_uring_buf) * configuration->buffers_count;

  struct io_uring_buf_reg buffer_request = {
      .ring_addr = (unsigned long)context->read_buffer_ring,
      .ring_entries = configuration->buffers_count,
      .bgid = 0,
  };

  int result = io_uring_register_buf_ring(&channel->ring, &buffer_request, 0);
  if (result)
  {
    log_error("ring register buffer failed: %d", result);
    return;
  }

  io_uring_buf_ring_init(context->read_buffer_ring);
  int buffer_index;
  for (buffer_index = 0; buffer_index < configuration->buffers_count; buffer_index++)
  {
    io_uring_buf_ring_add(context->read_buffer_ring,
                          transport_channel_get_buffer(context, buffer_index),
                          context->buffer_size,
                          buffer_index,
                          io_uring_buf_ring_mask(configuration->buffers_count),
                          buffer_index);
  }
  io_uring_buf_ring_advance(context->read_buffer_ring, configuration->buffers_count);

  mempool_create(&context->write_buffers, &channel->transport->cache, context->buffer_size);
}

transport_channel_t *transport_initialize_channel(transport_t *transport,
                                                  transport_controller_t *controller,
                                                  transport_channel_configuration_t *configuration,
                                                  Dart_Port read_port,
                                                  Dart_Port write_port)
{
  transport_channel_t *channel = malloc(sizeof(transport_channel_t));
  if (!channel)
  {
    return NULL;
  }

  channel->controller = controller;
  channel->transport = transport;

  channel->read_port = read_port;
  channel->write_port = write_port;

  struct transport_channel_context *context = malloc(sizeof(struct transport_channel_context));
  channel->context = context;
  channel->id = ++next_id;

  int32_t status = io_uring_queue_init(configuration->ring_size, &channel->ring, 0);
  if (status)
  {
    log_error("io_urig init error: %d", status);
    free(&channel->ring);
    free(context);
    return NULL;
  }

  transport_channel_setup_buffers(configuration, channel, context);

  context->channel = fiber_channel_new(1);
  context->balancer = (struct transport_balancer *)controller->balancer;
  context->balancer->add(context->balancer, channel);

  struct transport_message *message = malloc(sizeof(struct transport_message));
  message->action = TRANSPORT_ACTION_ADD_CHANNEL;
  message->data = (void *)channel;
  transport_controller_send(channel->controller, message);

  log_info("channel initialized");
  return channel;
}

static inline int transport_channel_select_buffer(struct transport_channel *channel, struct transport_channel_context *context, int fd)
{
  struct io_uring_sqe *sqe = provide_sqe(&channel->ring);
  io_uring_prep_read(sqe, fd, NULL, context->buffer_size, 0);
  io_uring_sqe_set_data64(sqe, (uint64_t)(fd | TRANSPORT_PAYLOAD_READ));
  sqe->flags |= IOSQE_BUFFER_SELECT;
  sqe->buf_group = 0;
  int result = io_uring_submit(&channel->ring);
  log_debug("channel select buffers");
  return result;
}

void transport_channel_accept(struct transport_channel *channel, int fd)
{
  log_debug("channel handle accept %d", fd);
  transport_channel_select_buffer(channel, (struct transport_channel_context *)channel->context, fd);
}

void *transport_channel_allocate_write_buffer(transport_channel_t *channel)
{
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  return mempool_alloc(&context->write_buffers);
}

int32_t transport_channel_send(transport_channel_t *channel, void *data, size_t size, int fd)
{
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  struct transport_message *message = malloc(sizeof(struct transport_message));
  message->action = TRANSPORT_ACTION_SEND;
  message->channel = context->channel;
  transport_payload_t *payload = malloc(sizeof(transport_payload_t));
  payload->data = data;
  payload->size = size;
  payload->fd = fd;
  message->data = payload;
  return transport_controller_send(channel->controller, message) ? 0 : -1;
}

static inline void transport_channel_recycle_buffer(struct transport_channel_context *context, int id)
{
  log_debug("channel recycle buffer");
  io_uring_buf_ring_add(context->read_buffer_ring,
                        transport_channel_get_buffer(context, id),
                        context->buffer_size,
                        id,
                        io_uring_buf_ring_mask(context->read_buffers_count),
                        0);
  io_uring_buf_ring_advance(context->read_buffer_ring, 1);
}

static inline void transport_channel_handle_read_cqe(struct transport_channel *channel, struct transport_channel_context *context, struct io_uring_cqe *cqe)
{
  int buffer_id = cqe->flags >> 16;
  int fd = cqe->user_data & ~TRANSPORT_PAYLOAD_ALL_FLAGS;
  uint32_t size = cqe->res;
  void *data = transport_channel_get_buffer(context, buffer_id);
  log_debug("channel read accept cqe res = %d, buffer_id = %d", cqe->res, buffer_id);
  if (likely(size))
  {
    transport_payload_t *payload = malloc(sizeof(transport_payload_t));
    void *output = malloc(size);
    memcpy(output, data, size);
    payload->data = output;
    payload->size = size;
    payload->fd = fd;
    log_debug("channel send read data to dart, data size = %d", size);
    dart_post_pointer(payload, channel->read_port);
  }
  transport_channel_recycle_buffer(context, buffer_id);
}

static inline void transport_channel_handle_write_cqe(struct transport_channel *channel, struct transport_channel_context *context, struct io_uring_cqe *cqe)
{
  log_debug("channel handle write cqe res = %d", cqe->res);
  transport_payload_t *payload = (transport_payload_t *)(cqe->user_data & ~TRANSPORT_PAYLOAD_ALL_FLAGS);
  log_debug("channel send write data to dart, data size = %d", payload->size);
  transport_channel_select_buffer(channel, context, payload->fd);
  dart_post_pointer(payload, channel->write_port);
}

int transport_channel_produce_loop(va_list input)
{
  struct transport_channel *channel = va_arg(input, struct transport_channel *);
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  log_info("channel sqe fiber started");
  while (channel->active)
  {
    void *message;
    if (likely(fiber_channel_get(context->channel, &message) == 0))
    {
      transport_payload_t *payload = (transport_payload_t *)((struct transport_message *)message)->data;
      free(message);
      struct io_uring_sqe *sqe = provide_sqe(&channel->ring);
      io_uring_prep_send(sqe, payload->fd, payload->data, payload->size, 0);
      io_uring_sqe_set_data64(sqe, (uint64_t)((intptr_t)payload | TRANSPORT_PAYLOAD_WRITE));
      io_uring_submit(&channel->ring);
      log_debug("channel send data to ring, data size = %d", payload->size);
    }
  }
  return 0;
}

int transport_channel_consume_loop(va_list input)
{
  struct transport_channel *channel = va_arg(input, struct transport_channel *);
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  struct io_uring *ring = &channel->ring;
  log_info("channel fiber cqe started");
  while (likely(channel->active))
  {
    int count = 0;
    unsigned int head;
    struct io_uring_cqe *cqe;
    while (!io_uring_cq_ready(ring))
    {
      fiber_sleep(0.0001);
    }
    io_uring_for_each_cqe(ring, head, cqe)
    {
      log_debug("channel %d process cqe with result '%s' and user_data %d", channel->id, cqe->res < 0 ? strerror(-cqe->res) : "ok", cqe->user_data);
      ++count;
      if (cqe->res < 0)
      {
        log_error("channel %d process cqe with result '%s' and user_data %d", channel->id, strerror(-cqe->res), cqe->user_data);
        continue;
      }

      if ((uint64_t)(cqe->user_data & TRANSPORT_PAYLOAD_READ) && (cqe->flags & IORING_CQE_F_BUFFER))
      {
        transport_channel_handle_read_cqe(channel, context, cqe);
        continue;
      }

      if ((uint64_t)(cqe->user_data & TRANSPORT_PAYLOAD_WRITE))
      {
        transport_channel_handle_write_cqe(channel, context, cqe);
        continue;
      }
    }
    io_uring_cq_advance(ring, count);
  }
  return 0;
}

int transport_channel_loop(va_list input)
{
  struct transport_channel *channel = va_arg(input, struct transport_channel *);
  log_info("channel fiber started");
  channel->active = true;
  struct fiber *sqe = fiber_new("sqe", transport_channel_produce_loop);
  struct fiber *cqe = fiber_new("cqe", transport_channel_consume_loop);
  fiber_set_joinable(sqe, true);
  fiber_set_joinable(cqe, true);
  fiber_start(sqe, channel);
  fiber_start(cqe, channel);
  fiber_join(sqe);
  fiber_join(cqe);
  return 0;
}

void transport_channel_free_write_payload(transport_channel_t *channel, transport_payload_t *payload)
{
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  mempool_free(&context->write_buffers, payload->data);
  free(payload);
}

void transport_channel_free_read_payload(transport_channel_t *channel, transport_payload_t *payload)
{
  free(payload->data);
  free(payload);
}

void transport_close_channel(transport_channel_t *channel)
{
  free(channel);
}