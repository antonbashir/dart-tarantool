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
#include "binding_acceptor.h"
#include "binding_common.h"
#include "binding_message.h"
#include "binding_channel.h"
#include "binding_balancer.h"
#include "binding_socket.h"
#include "fiber.h"

struct transport_acceptor_context
{
  struct io_uring ring;
  struct fiber_channel *channel;
  struct transport_balancer *balancer;
  struct sockaddr_in client_addres;
  socklen_t client_addres_length;
  int fd;
};

int transport_acceptor_loop(va_list input)
{
  struct transport_acceptor *acceptor = va_arg(input, struct transport_acceptor *);
  struct transport_acceptor_context *context = (struct transport_acceptor_context *)acceptor->context;
  log_info("acceptor fiber started");
  acceptor->active = true;
  while (acceptor->active)
  {
    if (!fiber_channel_is_empty(context->channel))
    {
      void *message;
      if (likely(fiber_channel_get(context->channel, &message) == 0))
      {
        intptr_t fd = (intptr_t)((struct transport_message *)message)->data;
        free(message);
        struct io_uring_sqe *sqe = io_uring_get_sqe(&context->ring);
        while (unlikely(sqe == NULL))
        {
          io_uring_submit(&context->ring);
          fiber_sleep(0);
          sqe = io_uring_get_sqe(&context->ring);
        }
        io_uring_prep_multishot_accept(sqe, (int)fd, (struct sockaddr *)&context->client_addres, &context->client_addres_length, 0);
        io_uring_sqe_set_data64(sqe, (uint64_t)TRANSPORT_PAYLOAD_ACCEPT);
        io_uring_submit(&context->ring);
      }
    }

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
      if (likely((uint64_t)(cqe->user_data & TRANSPORT_PAYLOAD_ACCEPT)))
      {
        int fd = cqe->res;
        struct io_uring_sqe *sqe = io_uring_get_sqe(&context->ring);
        while (unlikely(sqe == NULL))
        {
          fiber_sleep(0);
        }
        log_info("send accept to channel");
        struct transport_channel *channel = context->balancer->next(context->balancer);
        io_uring_prep_msg_ring(sqe, channel->ring.ring_fd, fd, (uint64_t)TRANSPORT_PAYLOAD_ACCEPT, 0);
        io_uring_submit(&context->ring);
        transport_acceptor_accept(acceptor);
      }
    }
    io_uring_cq_advance(&context->ring, count);
    fiber_sleep(0);
  }
  return 0;
}

transport_acceptor_t *transport_initialize_acceptor(transport_t *transport,
                                                    transport_controller_t *controller,
                                                    transport_acceptor_configuration_t *configuration,
                                                    const char *ip,
                                                    int32_t port)
{
  transport_acceptor_t *acceptor = smalloc(&transport->allocator, sizeof(transport_acceptor_t));
  if (!acceptor)
  {
    return NULL;
  }
  acceptor->controller = controller;
  acceptor->transport = transport;
  acceptor->server_ip = ip;
  acceptor->server_port = port;

  struct transport_acceptor_context *context = smalloc(&transport->allocator, sizeof(struct transport_acceptor_context));
  memset(&context->client_addres, 0, sizeof(context->client_addres));
  context->client_addres.sin_addr.s_addr = inet_addr(acceptor->server_ip);
  context->client_addres.sin_port = htons(acceptor->server_port);
  context->client_addres.sin_family = AF_INET;
  context->client_addres_length = sizeof(context->client_addres);
  context->balancer = (struct transport_balancer *)controller->balancer;
  context->fd = transport_socket_create();
  if (transport_socket_bind(context->fd, ip, port, configuration->backlog))
  {
    return NULL;
  }

  acceptor->context = context;

  int32_t status = io_uring_queue_init(configuration->ring_size, &context->ring, 0);
  if (status)
  {
    log_error("io_urig init error: %d", status);
    free(&context->ring);
    smfree(&transport->allocator, context, sizeof(struct transport_acceptor_context));
    return NULL;
  }

  context->channel = fiber_channel_new(configuration->ring_size);

  struct transport_message *message = malloc(sizeof(struct transport_message));
  message->action = TRANSPORT_ACTION_ADD_ACCEPTOR;
  message->data = (void *)acceptor;
  transport_controller_send(acceptor->controller, message);

  log_info("acceptor initialized");
  return acceptor;
}

void transport_close_acceptor(transport_acceptor_t *acceptor)
{
  struct transport_acceptor_context *context = (struct transport_acceptor_context *)acceptor->context;
  io_uring_queue_exit(&context->ring);
  smfree(&acceptor->transport->allocator, acceptor, sizeof(transport_acceptor_t));
}

int32_t transport_acceptor_accept(transport_acceptor_t *acceptor)
{
  struct transport_acceptor_context *context = (struct transport_acceptor_context *)acceptor->context;
  struct transport_message *message = malloc(sizeof(struct transport_message));
  message->action = TRANSPORT_ACTION_SEND;
  message->channel = context->channel;
  message->data = (void *)(intptr_t)context->fd;
  return transport_controller_send(acceptor->controller, message) ? 0 : -1;
}