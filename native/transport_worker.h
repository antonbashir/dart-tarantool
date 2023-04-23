#ifndef TRANSPORT_WORKER_H
#define TRANSPORT_WORKER_H

#include <stdint.h>
#include <stdio.h>
#include "transport_common.h"
#include "transport_listener_pool.h"
#include "transport_client.h"
#include "transport_server.h"
#include "transport_collections.h"
#include "transport_buffers_pool.h"

#if defined(__cplusplus)
extern "C"
{
#endif
  typedef struct transport_worker_sequence_element
  {
    uint16_t buffer_id;
    struct rlist link;
  } transport_worker_sequence_element_t;

  typedef struct transport_worker_configuration
  {
    uint16_t buffers_count;
    uint16_t sequences_count;
    uint32_t buffer_size;
    size_t ring_size;
    int ring_flags;
    uint64_t timeout_checker_period_millis;
  } transport_worker_configuration_t;

  typedef struct transport_worker
  {
    uint8_t id;
    struct transport_buffers_pool free_buffers;
    struct transport_buffers_pool free_sequences;
    struct io_uring *ring;
    transport_listener_pool_t *listeners;
    struct iovec *buffers;
    uint32_t buffer_size;
    uint32_t sequences_count;
    uint16_t buffers_count;
    uint64_t timeout_checker_period_millis;
    struct msghdr *inet_used_messages;
    struct msghdr *unix_used_messages;
    struct mh_events_t *events;
    transport_worker_sequence_element_t *sequences;
    transport_worker_sequence_element_t *sequence_buffers;
  } transport_worker_t;

  int transport_worker_initialize(transport_worker_t *worker, transport_worker_configuration_t *configuration, uint8_t id);

  void transport_worker_custom(transport_worker_t *worker, uint32_t id, uint32_t custom_data);
  void transport_worker_add_write(transport_worker_t *worker,
                                  uint32_t fd,
                                  uint16_t buffer_id,
                                  uint32_t offset,
                                  int64_t timeout,
                                  uint16_t event,
                                  uint8_t sqe_flags,
                                  uint16_t sequence_id);
  void transport_worker_add_read(transport_worker_t *worker,
                                 uint32_t fd,
                                 uint16_t buffer_id,
                                 uint32_t offset,
                                 int64_t timeout,
                                 uint16_t event,
                                 uint8_t sqe_flags,
                                 uint16_t sequence_id);
  void transport_worker_add_send_message(transport_worker_t *worker,
                                         uint32_t fd,
                                         uint16_t buffer_id,
                                         struct sockaddr *address,
                                         transport_socket_family_t socket_family,
                                         int message_flags,
                                         int64_t timeout,
                                         uint16_t event,
                                         uint8_t sqe_flags,
                                         uint16_t sequence_id);
  void transport_worker_add_receive_message(transport_worker_t *worker,
                                            uint32_t fd,
                                            uint16_t buffer_id,
                                            transport_socket_family_t socket_family,
                                            int message_flags,
                                            int64_t timeout,
                                            uint16_t event,
                                            uint8_t sqe_flags,
                                            uint16_t sequence_id);
  void transport_worker_connect(transport_worker_t *worker, transport_client_t *client, int64_t timeout);
  void transport_worker_accept(transport_worker_t *worker, transport_server_t *server);
  void transport_worker_submit(transport_worker_t *worker);

  void transport_worker_cancel_by_fd(transport_worker_t *worker, int fd);

  void transport_worker_check_event_timeouts(transport_worker_t *worker);
  void transport_worker_remove_event(transport_worker_t *worker, uint64_t data);

  int32_t transport_worker_get_buffer(transport_worker_t *worker);
  void transport_worker_release_buffer(transport_worker_t *worker, uint16_t buffer_id);

  int32_t transport_worker_get_sequence(transport_worker_t *worker);
  void transport_worker_release_sequence(transport_worker_t *worker, uint16_t sequence_id);

  void transport_worker_sequence_add_buffer(transport_worker_t *worker, uint16_t sequence_id, uint16_t buffer_id);
  transport_worker_sequence_element_t *transport_worker_sequence_get_last_element(transport_worker_t *worker, uint16_t sequence_id);
  transport_worker_sequence_element_t *transport_worker_sequence_get_first_element(transport_worker_t *worker, uint16_t sequence_id);
  transport_worker_sequence_element_t *transport_worker_sequence_get_next_element(transport_worker_t *worker, uint16_t sequence_id, transport_worker_sequence_element_t *element);
  void transport_worker_sequence_delete_element(transport_worker_t *worker, uint16_t sequence_id, transport_worker_sequence_element_t *element);
  void transport_worker_sequence_release_element(transport_worker_t *worker, uint16_t sequence_id, transport_worker_sequence_element_t *element);

  struct sockaddr *transport_worker_get_datagram_address(transport_worker_t *worker, transport_socket_family_t socket_family, int buffer_id);

  int transport_worker_peek(uint32_t cqe_count, struct io_uring_cqe **cqes, struct io_uring *ring);

  void transport_worker_destroy(transport_worker_t *worker);

#if defined(__cplusplus)
}
#endif

#endif