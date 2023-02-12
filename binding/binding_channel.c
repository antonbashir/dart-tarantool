#include "binding_channel.h"
#include "dart/dart_api.h"
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
#include "binding_common.h"
#include "binding_balancer.h"
#include "binding_message.h"
#include "fiber_channel.h"
#include "fiber.h"

struct transport_channel_message
{
  void *data;
  size_t size;
  int fd;
  int buffer_id;
};

struct transport_channel_context
{
  struct io_uring ring;
  struct fiber_channel *channel;
  struct transport_balancer *balancer;
  struct io_uring_buf_ring *buffer_ring;
  size_t buffer_count;
  int buffer_shift;
  unsigned char *buffer_base;
};

static inline size_t transport_buffer_size(struct transport_channel_context *context)
{
  return 1U << context->buffer_shift;
}

static inline unsigned char *transport_get_buffer(struct transport_channel_context *context, int id)
{
  return context->buffer_base + (id << context->buffer_shift);
}

static inline void transport_channel_recycle_buffer(struct transport_channel_context *context, int id)
{
  io_uring_buf_ring_add(context->buffer_ring,
                        transport_get_buffer(context, id),
                        transport_buffer_size(context),
                        id,
                        io_uring_buf_ring_mask(context->buffer_count),
                        0);
  io_uring_buf_ring_advance(context->buffer_ring, 1);
}

static inline void dart_post_pointer(void *pointer, Dart_Port port)
{
  Dart_CObject dart_object;
  dart_object.type = Dart_CObject_kInt64;
  dart_object.value.as_int64 = (int64_t)pointer;
  Dart_PostCObject(port, &dart_object);
};

static inline void transport_channel_setup_buffers(transport_channel_configuration_t *configuration, struct transport_channel_context *context)
{
  size_t buffer_ring_size = (sizeof(struct io_uring_buf) + configuration->buffer_size) * configuration->buffers_count;
  void *buffer_memory = mmap(NULL, buffer_ring_size, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, 0, 0);
  if (buffer_memory == MAP_FAILED)
  {
    return NULL;
  }
  context->buffer_ring = (struct io_uring_buf_ring *)buffer_memory;
  io_uring_buf_ring_init(context->buffer_ring);

  struct io_uring_buf_reg buffer_request = {
      .ring_addr = (unsigned long)context->buffer_ring,
      .ring_entries = configuration->buffers_count,
      .bgid = 0,
  };
  unsigned char *buffer_base = (unsigned char *)context->buffer_ring + sizeof(struct io_uring_buf) * configuration->buffers_count;

  if (!io_uring_register_buf_ring(&context->ring, &buffer_request, 0))
  {
    return NULL;
  }

  int buffer_index;
  for (buffer_index = 0; buffer_index < configuration->buffers_count; buffer_index++)
  {
    io_uring_buf_ring_add(context->buffer_ring,
                          transport_get_buffer(context, buffer_index),
                          configuration->buffer_size,
                          buffer_index,
                          io_uring_buf_ring_mask(configuration->buffers_count),
                          buffer_index);
  }

  io_uring_buf_ring_advance(context->buffer_ring, configuration->buffers_count);
}

transport_channel_t *transport_initialize_channel(transport_t *transport,
                                                  transport_controller_t *controller,
                                                  transport_channel_configuration_t *configuration,
                                                  Dart_Port read_port,
                                                  Dart_Port write_port,
                                                  Dart_Port accept_port,
                                                  Dart_Port connect_port)
{
  transport_channel_t *channel = smalloc(&transport->allocator, sizeof(transport_channel_t));
  if (!channel)
  {
    return NULL;
  }

  channel->controller = controller;
  channel->transport = transport;

  channel->read_port = read_port;
  channel->write_port = write_port;
  channel->accept_port = accept_port;
  channel->connect_port = connect_port;

  struct transport_channel_context *context = smalloc(&transport->allocator, sizeof(struct transport_channel_context));
  channel->context = context;

  int32_t status = io_uring_queue_init(configuration->ring_size, &context->ring, IORING_SETUP_SUBMIT_ALL | IORING_SETUP_COOP_TASKRUN | IORING_SETUP_CQSIZE);
  if (status)
  {
    log_error("io_urig init error: %d", status);
    free(&context->ring);
    smfree(&transport->allocator, context, sizeof(struct transport_channel_context));
    return NULL;
  }

  context->channel = fiber_channel_new(configuration->ring_size);

  transport_channel_setup_buffers(configuration, context);

  context->balancer->add(channel);

  return channel;
}

void transport_close_channel(transport_channel_t *channel)
{
  smfree(&channel->transport->allocator, channel, sizeof(transport_channel_t));
}

static inline int transport_channel_select_buffer(struct transport_channel_context *context, int fd)
{
  struct io_uring_sqe *sqe;

  struct io_uring_sqe *sqe = io_uring_get_sqe(&context->ring);
  while (unlikely(sqe == NULL))
  {
    io_uring_submit(&context->ring);
    fiber_sleep(0);
    sqe = io_uring_get_sqe(&context->ring);
  }

  io_uring_prep_recv_multishot(sqe, fd, NULL, transport_buffer_size(context), 0);
  io_uring_sqe_set_data(sqe, fd | TRANSPORT_PAYLOAD_READ);
  sqe->flags |= IOSQE_FIXED_FILE;
  sqe->flags |= IOSQE_BUFFER_SELECT;
  sqe->buf_group = 0;
  io_uring_submit(&context->ring);
  return 0;
}

int32_t transport_channel_send(transport_channel_t *channel, void *data, size_t size, int fd)
{
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  struct transport_message *message = malloc(sizeof(struct transport_message *));
  message->channel = context->channel;
  struct transport_channel_message *channel_message = malloc(sizeof(struct transport_channel_message));
  channel_message->data = data;
  channel_message->size = size;
  channel_message->fd = fd;
  message->data = channel_message;
  return transport_controller_send(channel->controller, message) ? 0 : -1;
}

int transport_channel_loop(va_list input)
{
  struct transport_channel *channel = va_arg(input, struct transport_channel *);
  struct transport_channel_context *context = (struct transport_channel_context *)channel->context;
  while (channel->active)
  {
    int count = 0;
    unsigned int head;
    struct io_uring_cqe *cqe;
    io_uring_for_each_cqe(&context->ring, head, cqe)
    {
      ++count;
      if (unlikely(cqe->res < 0))
      {
        continue;
      }

      if (cqe->user_data & (TRANSPORT_PAYLOAD_ACCEPT | TRANSPORT_PAYLOAD_CONNECT))
      {
        io_uring_register_files(&context->ring, cqe->res, 1);
        transport_channel_select_buffer(context, cqe->res);
        continue;
      }

      int buffer_id = cqe->flags >> 16;

      if (cqe->user_data & TRANSPORT_PAYLOAD_READ)
      {
        void *payload = transport_get_buffer(context, buffer_id);
        if (payload)
        {
          uint32_t length = cqe->res;
          void *output = malloc(length);
          memcpy(output, payload, length);
          dart_post_pointer(channel->read_port, output);
        }

        if (!fiber_channel_is_empty(context->channel))
        {
          struct transport_message *message;
          if (likely(fiber_channel_get(context->channel, &message) == 0))
          {
            struct transport_channel_message *data = (struct transport_channel_message *)message->data;
            free(message);
            struct io_uring_sqe *sqe = io_uring_get_sqe(&context->ring);
            while (unlikely(sqe == NULL))
            {
              io_uring_submit(&context->ring);
              fiber_sleep(0);
              sqe = io_uring_get_sqe(&context->ring);
            }
            data->buffer_id = buffer_id;
            void *buffer = transport_get_buffer(context, buffer_id);
            memcpy(buffer, data->data, data->size);
            io_uring_prep_sendmsg_zc(sqe, data->fd, buffer, 0);
            io_uring_sqe_set_data(sqe, (intptr_t)message | TRANSPORT_PAYLOAD_WRITE);
            sqe->flags |= IOSQE_FIXED_FILE;
            io_uring_submit(&context->ring);
          }
        }

        transport_channel_select_buffer(context, cqe->user_data & -TRANSPORT_PAYLOAD_ALL_FLAGS);

        continue;
      }

      if (cqe->user_data & TRANSPORT_PAYLOAD_WRITE)
      {
        struct transport_channel_message *data = (struct transport_channel_message *)(cqe->user_data & -TRANSPORT_PAYLOAD_ALL_FLAGS);
        void *payload = transport_get_buffer(context, buffer_id);
        if (payload)
        {
          uint32_t length = cqe->res;
          void *output = malloc(length);
          memcpy(output, payload, length);
          dart_post_pointer(channel->read_port, output);
        }
        transport_channel_recycle_buffer(context, buffer_id);
        free(data->data);
        free(data);
        continue;
      }
    }
    io_uring_cq_advance(&context->ring, count);
    fiber_sleep(0);
  }
  return 0;
}