#ifndef TRANSPORT_CLIENT_H_INCLUDED
#define TRANSPORT_CLIENT_H_INCLUDED

#include <stdbool.h>
#include <netinet/in.h>
#include <sys/un.h>
#include <stdint.h>
#include <liburing.h>
#include <stdio.h>
#include "transport_constants.h"

#if defined(__cplusplus)
extern "C"
{
#endif

  typedef struct transport_client_configuration
  {
    uint32_t receive_buffer_size;
    uint32_t send_buffer_size;
  } transport_client_configuration_t;

  typedef struct transport_client
  {
    int fd;
    struct sockaddr_in inet_destination_address;
    struct sockaddr_in inet_source_address;
    struct sockaddr_un unix_destination_address;
    struct sockaddr_un unix_source_address;
    socklen_t client_address_length;
    transport_socket_family_t family;
  } transport_client_t;

  transport_client_t *transport_client_initialize_tcp(transport_client_configuration_t *configuration,
                                                      const char *ip,
                                                      int32_t port);

  transport_client_t *transport_client_initialize_udp(transport_client_configuration_t *configuration,
                                                      const char *destination_ip,
                                                      int32_t destination_port,
                                                      const char *source_ip,
                                                      int32_t source_port);

  transport_client_t *transport_client_initialize_unix_stream(transport_client_configuration_t *configuration,
                                                              const char *path);

  transport_client_t *transport_client_initialize_unix_dgram(transport_client_configuration_t *configuration,
                                                             const char *destination_path,
                                                             const char *source_path);

  struct sockaddr *transport_client_get_destination_address(transport_client_t *client);

  void transport_client_destroy(transport_client_t *client);
#if defined(__cplusplus)
}
#endif

#endif
