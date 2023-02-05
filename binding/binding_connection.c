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
#include "binding_connection.h"
#include "binding_common.h"

transport_connection_t *transport_initialize_connection(transport_t *transport,
                                                        transport_controller_t *controller,
                                                        transport_connection_configuration_t *configuration,
                                                        Dart_Port accept_port,
                                                        Dart_Port connect_port)
{
  transport_connection_t *connection = smalloc(&transport->allocator, sizeof(transport_connection_t));
  if (!connection)
  {
    return NULL;
  }
  connection->controller = controller;
  connection->transport = transport;

  mempool_create(&connection->accept_payload_pool, &transport->cache, sizeof(transport_accept_payload_t));

  connection->accept_port = accept_port;
  connection->connect_port = connect_port;

  return connection;
}

void transport_close_connection(transport_connection_t *connection)
{
  mempool_destroy(&connection->accept_payload_pool);

  smfree(&connection->transport->allocator, connection, sizeof(transport_connection_t));
}

int32_t transport_connection_queue_accept(transport_connection_t *connection, int32_t server_socket_fd)
{
  transport_accept_payload_t *payload = mempool_alloc(&connection->accept_payload_pool);
  if (!payload)
  {
    return -1;
  }
  memset(&payload->client_addres, 0, sizeof(payload->client_addres));
  payload->client_addres_length = sizeof(payload->client_addres);
  payload->fd = server_socket_fd;
  payload->type = TRANSPORT_PAYLOAD_ACCEPT;

  //log_info("queue accept message");
  transport_controller_send(connection->controller, transport_controller_create_message(connection->controller, connection->accept_port, payload, TRANSPORT_PAYLOAD_ACCEPT));
}

int32_t transport_connection_queue_connect(transport_connection_t *connection, int32_t socket_fd, const char *ip, int32_t port)
{

  transport_accept_payload_t *payload = mempool_alloc(&connection->accept_payload_pool);
  if (!payload)
  {
    return -1;
  }
  memset(&payload->client_addres, 0, sizeof(payload->client_addres));
  payload->client_addres.sin_addr.s_addr = inet_addr(ip);
  payload->client_addres.sin_port = htons(port);
  payload->client_addres.sin_family = AF_INET;
  payload->client_addres_length = sizeof(payload->client_addres);
  payload->fd = socket_fd;
  payload->type = TRANSPORT_PAYLOAD_CONNECT;

  //log_info("queue connect message");
  transport_controller_send(connection->controller, transport_controller_create_message(connection->controller, connection->connect_port, payload, TRANSPORT_PAYLOAD_CONNECT));
}

transport_accept_payload_t *transport_connection_allocate_accept_payload(transport_connection_t *connection)
{
  return (transport_accept_payload_t *)mempool_alloc(&connection->accept_payload_pool);
}

void transport_connection_free_accept_payload(transport_connection_t *connection, transport_accept_payload_t *payload)
{
  //log_info("free accept message");
  mempool_free(&connection->accept_payload_pool, payload);
}
