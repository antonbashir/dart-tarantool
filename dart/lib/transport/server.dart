import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:iouring_transport/transport/extensions.dart';

import 'bindings.dart';
import 'channels.dart';
import 'communicator.dart';
import 'configuration.dart';
import 'constants.dart';
import 'defaults.dart';
import 'callbacks.dart';

class TransportServer {
  final Pointer<transport_server_t> pointer;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportBindings _bindings;
  final int readTimeout;
  final int writeTimeout;
  final Transportcallbacks callbacks;
  final Queue<Completer<int>> _bufferFinalizers;
  final TransportServerRegistry registry;

  late final int fd;
  late final Pointer<iovec> _buffers;

  var _active = true;
  bool get active => _active;
  final _closer = Completer();

  TransportServer(
    this.pointer,
    this._workerPointer,
    this._bindings,
    this.callbacks,
    this.readTimeout,
    this.writeTimeout,
    this._bufferFinalizers,
    this.registry,
  ) {
    fd = pointer.ref.fd;
    _buffers = _workerPointer.ref.buffers;
  }

  @pragma(preferInlinePragma)
  void accept(Pointer<transport_worker_t> workerPointer, void Function(TransportServerStreamCommunicator communicator) onAccept) {
    callbacks.setAccept(fd, (channel) => onAccept(TransportServerStreamCommunicator(this, channel)));
    _bindings.transport_worker_accept(
      workerPointer,
      pointer,
    );
  }

  @pragma(preferInlinePragma)
  void releaseBuffer(int bufferId) {
    _bindings.transport_worker_release_buffer(_workerPointer, bufferId);
    if (_bufferFinalizers.isNotEmpty) _bufferFinalizers.removeLast().complete(bufferId);
  }

  @pragma(preferInlinePragma)
  void reuseBuffer(int bufferId) {
    _bindings.transport_worker_reuse_buffer(_workerPointer, bufferId);
    if (_bufferFinalizers.isNotEmpty) _bufferFinalizers.removeLast().complete(bufferId);
  }

  @pragma(preferInlinePragma)
  Uint8List readBuffer(int bufferId) {
    final buffer = _buffers[bufferId];
    final bufferBytes = buffer.iov_base.cast<Uint8>();
    return bufferBytes.asTypedList(buffer.iov_len);
  }

  @pragma(preferInlinePragma)
  Pointer<sockaddr> getDatagramEndpointAddress(int bufferId) => _bindings.transport_worker_get_endpoint_address(_workerPointer, pointer.ref.family, bufferId);

  @pragma(preferInlinePragma)
  void onRemove() {
    if (!_active) _closer.complete();
  }

  Future<void> close() async {
    if (_active) {
      _active = false;
      _bindings.transport_close_descritor(pointer.ref.fd);
      await _closer.future;
      _bindings.transport_server_destroy(pointer);
    }
  }
}

class TransportServerRegistry {
  final _servers = <int, TransportServer>{};
  final _serversByClients = <int, TransportServer>{};

  final Pointer<transport_worker_t> _workerPointer;
  final TransportBindings _bindings;
  final Transportcallbacks _callbacks;
  final Queue<Completer<int>> _bufferFinalizers;

  TransportServerRegistry(this._bindings, this._callbacks, this._workerPointer, this._bufferFinalizers);

  TransportServer createTcp(String host, int port, {TransportTcpServerConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.tcpServer();
    final instance = using(
      (Arena arena) => TransportServer(
        _bindings.transport_server_initialize_tcp(
          _tcpConfiguration(configuration!, arena),
          host.toNativeUtf8(allocator: arena).cast(),
          port,
        ),
        _workerPointer,
        _bindings,
        _callbacks,
        configuration.readTimeout.inSeconds,
        configuration.writeTimeout.inSeconds,
        _bufferFinalizers,
        this,
      ),
    );
    _servers[instance.pointer.ref.fd] = instance;
    return instance;
  }

  TransportServer createUdp(String host, int port, {TransportUdpServerConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.udpServer();
    final instance = using(
      (Arena arena) {
        final pointer = _bindings.transport_server_initialize_udp(
          _udpConfiguration(configuration!, arena),
          host.toNativeUtf8(allocator: arena).cast(),
          port,
        );
        if (configuration.multicastManager != null) {
          configuration.multicastManager!.subscribe(
            onAddMembership: (configuration) => using(
              (arena) => _bindings.transport_socket_multicast_add_membership(
                pointer.ref.fd,
                configuration.groupAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.localAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.getMemberShipIndex(_bindings),
              ),
            ),
            onDropMembership: (configuration) => using(
              (arena) => _bindings.transport_socket_multicast_drop_membership(
                pointer.ref.fd,
                configuration.groupAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.localAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.getMemberShipIndex(_bindings),
              ),
            ),
            onAddSourceMembership: (configuration) => using(
              (arena) => _bindings.transport_socket_multicast_add_source_membership(
                pointer.ref.fd,
                configuration.groupAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.localAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.sourceAddress.toNativeUtf8(allocator: arena).cast(),
              ),
            ),
            onDropSourceMembership: (configuration) => using(
              (arena) => _bindings.transport_socket_multicast_drop_source_membership(
                pointer.ref.fd,
                configuration.groupAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.localAddress.toNativeUtf8(allocator: arena).cast(),
                configuration.sourceAddress.toNativeUtf8(allocator: arena).cast(),
              ),
            ),
          );
        }
        return TransportServer(
          pointer,
          _workerPointer,
          _bindings,
          _callbacks,
          configuration.readTimeout.inSeconds,
          configuration.writeTimeout.inSeconds,
          _bufferFinalizers,
          this,
        );
      },
    );
    _servers[instance.pointer.ref.fd] = instance;
    return instance;
  }

  TransportServer createUnixStream(String path, {TransportUnixStreamServerConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.unixStreamServer();
    final instance = using(
      (Arena arena) => TransportServer(
        _bindings.transport_server_initialize_unix_stream(
          _unixStreamConfiguration(configuration!, arena),
          path.toNativeUtf8(allocator: arena).cast(),
        ),
        _workerPointer,
        _bindings,
        _callbacks,
        configuration.readTimeout.inSeconds,
        configuration.writeTimeout.inSeconds,
        _bufferFinalizers,
        this,
      ),
    );
    _servers[instance.pointer.ref.fd] = instance;
    return instance;
  }

  TransportServer createUnixDatagram(String path, {TransportUnixDatagramServerConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.unixDatagramServer();
    final instance = using(
      (Arena arena) => TransportServer(
        _bindings.transport_server_initialize_unix_dgram(
          _unixDatagramConfiguration(configuration!, arena),
          path.toNativeUtf8(allocator: arena).cast(),
        ),
        _workerPointer,
        _bindings,
        _callbacks,
        configuration.readTimeout.inSeconds,
        configuration.writeTimeout.inSeconds,
        _bufferFinalizers,
        this,
      ),
    );
    _servers[instance.pointer.ref.fd] = instance;
    return instance;
  }

  @pragma(preferInlinePragma)
  TransportServer? getByServer(int fd) => _servers[fd];

  @pragma(preferInlinePragma)
  TransportServer? getByClient(int fd) => _serversByClients[fd];

  @pragma(preferInlinePragma)
  void addClient(int serverFd, int clientFd) => _serversByClients[clientFd] = _servers[serverFd]!;

  @pragma(preferInlinePragma)
  void removeClient(int fd) => _serversByClients.remove(fd);

  @pragma(preferInlinePragma)
  void removeServer(int fd) => _servers.remove(fd)?.onRemove();

  Future<void> close() async {
    await Future.wait(_servers.values.map((server) => server.close()));
  }

  Pointer<transport_server_configuration_t> _tcpConfiguration(TransportTcpServerConfiguration serverConfiguration, Allocator allocator) {
    final nativeServerConfiguration = allocator<transport_server_configuration_t>();
    int flags = 0;
    if (serverConfiguration.socketNonblock == true) flags |= transportSocketOptionSocketNonblock;
    if (serverConfiguration.socketClockexec == true) flags |= transportSocketOptionSocketClockexec;
    if (serverConfiguration.socketReuseAddress == true) flags |= transportSocketOptionSocketReuseaddr;
    if (serverConfiguration.socketReusePort == true) flags |= transportSocketOptionSocketReuseport;
    if (serverConfiguration.socketKeepalive == true) flags |= transportSocketOptionSocketKeepalive;
    if (serverConfiguration.ipFreebind == true) flags |= transportSocketOptionIpFreebind;
    if (serverConfiguration.tcpQuickack == true) flags |= transportSocketOptionTcpQuickack;
    if (serverConfiguration.tcpDeferAccept == true) flags |= transportSocketOptionTcpDeferAccept;
    if (serverConfiguration.tcpFastopen == true) flags |= transportSocketOptionTcpFastopen;
    if (serverConfiguration.tcpNodelay == true) flags |= transportSocketOptionTcpNodelay;
    if (serverConfiguration.socketMaxConnections != null) {
      nativeServerConfiguration.ref.socket_max_connections = serverConfiguration.socketMaxConnections!;
    }
    if (serverConfiguration.socketReceiveBufferSize != null) {
      flags |= transportSocketOptionSocketRcvbuf;
      nativeServerConfiguration.ref.socket_receive_buffer_size = serverConfiguration.socketReceiveBufferSize!;
    }
    if (serverConfiguration.socketSendBufferSize != null) {
      flags |= transportSocketOptionSocketSndbuf;
      nativeServerConfiguration.ref.socket_send_buffer_size = serverConfiguration.socketSendBufferSize!;
    }
    if (serverConfiguration.socketReceiveLowAt != null) {
      flags |= transportSocketOptionSocketRcvlowat;
      nativeServerConfiguration.ref.socket_receive_low_at = serverConfiguration.socketReceiveLowAt!;
    }
    if (serverConfiguration.socketSendLowAt != null) {
      flags |= transportSocketOptionSocketSndlowat;
      nativeServerConfiguration.ref.socket_send_low_at = serverConfiguration.socketSendLowAt!;
    }
    if (serverConfiguration.ipTtl != null) {
      flags |= transportSocketOptionIpTtl;
      nativeServerConfiguration.ref.ip_ttl = serverConfiguration.ipTtl!;
    }
    if (serverConfiguration.tcpKeepAliveIdle != null) {
      flags |= transportSocketOptionTcpKeepidle;
      nativeServerConfiguration.ref.tcp_keep_alive_idle = serverConfiguration.tcpKeepAliveIdle!;
    }
    if (serverConfiguration.tcpKeepAliveMaxCount != null) {
      flags |= transportSocketOptionTcpKeepcnt;
      nativeServerConfiguration.ref.tcp_keep_alive_max_count = serverConfiguration.tcpKeepAliveMaxCount!;
    }
    if (serverConfiguration.tcpKeepAliveIdle != null) {
      flags |= transportSocketOptionTcpKeepintvl;
      nativeServerConfiguration.ref.tcp_keep_alive_individual_count = serverConfiguration.tcpKeepAliveIdle!;
    }
    if (serverConfiguration.tcpMaxSegmentSize != null) {
      flags |= transportSocketOptionTcpMaxseg;
      nativeServerConfiguration.ref.tcp_max_segment_size = serverConfiguration.tcpMaxSegmentSize!;
    }
    if (serverConfiguration.tcpSynCount != null) {
      flags |= transportSocketOptionTcpSyncnt;
      nativeServerConfiguration.ref.tcp_syn_count = serverConfiguration.tcpSynCount!;
    }
    nativeServerConfiguration.ref.socket_configuration_flags = flags;
    return nativeServerConfiguration;
  }

  Pointer<transport_server_configuration_t> _udpConfiguration(TransportUdpServerConfiguration serverConfiguration, Allocator allocator) {
    final nativeServerConfiguration = allocator<transport_server_configuration_t>();
    int flags = 0;
    if (serverConfiguration.socketNonblock == true) flags |= transportSocketOptionSocketNonblock;
    if (serverConfiguration.socketClockexec == true) flags |= transportSocketOptionSocketClockexec;
    if (serverConfiguration.socketReuseAddress == true) flags |= transportSocketOptionSocketReuseaddr;
    if (serverConfiguration.socketReusePort == true) flags |= transportSocketOptionSocketReuseport;
    if (serverConfiguration.socketBroadcast == true) flags |= transportSocketOptionSocketBroadcast;
    if (serverConfiguration.ipFreebind == true) flags |= transportSocketOptionIpFreebind;
    if (serverConfiguration.ipMulticastAll == true) flags |= transportSocketOptionIpMulticastAll;
    if (serverConfiguration.ipMulticastLoop == true) flags |= transportSocketOptionIpMulticastLoop;
    if (serverConfiguration.socketReceiveBufferSize != null) {
      flags |= transportSocketOptionSocketRcvbuf;
      nativeServerConfiguration.ref.socket_receive_buffer_size = serverConfiguration.socketReceiveBufferSize!;
    }
    if (serverConfiguration.socketSendBufferSize != null) {
      flags |= transportSocketOptionSocketSndbuf;
      nativeServerConfiguration.ref.socket_send_buffer_size = serverConfiguration.socketSendBufferSize!;
    }
    if (serverConfiguration.socketReceiveLowAt != null) {
      flags |= transportSocketOptionSocketRcvlowat;
      nativeServerConfiguration.ref.socket_receive_low_at = serverConfiguration.socketReceiveLowAt!;
    }
    if (serverConfiguration.socketSendLowAt != null) {
      flags |= transportSocketOptionSocketSndlowat;
      nativeServerConfiguration.ref.socket_send_low_at = serverConfiguration.socketSendLowAt!;
    }
    if (serverConfiguration.ipTtl != null) {
      flags |= transportSocketOptionIpTtl;
      nativeServerConfiguration.ref.ip_ttl = serverConfiguration.ipTtl!;
    }
    if (serverConfiguration.ipMulticastTtl != null) {
      flags |= transportSocketOptionIpMulticastTtl;
      nativeServerConfiguration.ref.ip_multicast_ttl = serverConfiguration.ipMulticastTtl!;
    }
    if (serverConfiguration.ipMulticastInterface != null) {
      flags |= transportSocketOptionIpMulticastIf;
      final interface = serverConfiguration.ipMulticastInterface!;
      nativeServerConfiguration.ref.ip_multicast_interface = _bindings.transport_socket_multicast_create_request(
        interface.groupAddress.toNativeUtf8(allocator: allocator).cast(),
        interface.localAddress.toNativeUtf8(allocator: allocator).cast(),
        interface.getMemberShipIndex(_bindings),
      );
    }
    nativeServerConfiguration.ref.socket_configuration_flags = flags;
    return nativeServerConfiguration;
  }

  Pointer<transport_server_configuration_t> _unixStreamConfiguration(TransportUnixStreamServerConfiguration serverConfiguration, Allocator allocator) {
    final nativeServerConfiguration = allocator<transport_server_configuration_t>();
    int flags = 0;
    if (serverConfiguration.socketNonblock == true) flags |= transportSocketOptionSocketNonblock;
    if (serverConfiguration.socketClockexec == true) flags |= transportSocketOptionSocketClockexec;
    if (serverConfiguration.socketReuseAddress == true) flags |= transportSocketOptionSocketReuseaddr;
    if (serverConfiguration.socketReusePort == true) flags |= transportSocketOptionSocketReuseport;
    if (serverConfiguration.socketKeepalive == true) flags |= transportSocketOptionSocketKeepalive;
    if (serverConfiguration.socketMaxConnections != null) {
      nativeServerConfiguration.ref.socket_max_connections = serverConfiguration.socketMaxConnections!;
    }
    if (serverConfiguration.socketReceiveBufferSize != null) {
      flags |= transportSocketOptionSocketRcvbuf;
      nativeServerConfiguration.ref.socket_receive_buffer_size = serverConfiguration.socketReceiveBufferSize!;
    }
    if (serverConfiguration.socketSendBufferSize != null) {
      flags |= transportSocketOptionSocketSndbuf;
      nativeServerConfiguration.ref.socket_send_buffer_size = serverConfiguration.socketSendBufferSize!;
    }
    if (serverConfiguration.socketReceiveLowAt != null) {
      flags |= transportSocketOptionSocketRcvlowat;
      nativeServerConfiguration.ref.socket_receive_low_at = serverConfiguration.socketReceiveLowAt!;
    }
    if (serverConfiguration.socketSendLowAt != null) {
      flags |= transportSocketOptionSocketSndlowat;
      nativeServerConfiguration.ref.socket_send_low_at = serverConfiguration.socketSendLowAt!;
    }
    nativeServerConfiguration.ref.socket_configuration_flags = flags;
    return nativeServerConfiguration;
  }

  Pointer<transport_server_configuration_t> _unixDatagramConfiguration(TransportUnixDatagramServerConfiguration serverConfiguration, Allocator allocator) {
    final nativeServerConfiguration = allocator<transport_server_configuration_t>();
    int flags = 0;
    if (serverConfiguration.socketNonblock == true) flags |= transportSocketOptionSocketNonblock;
    if (serverConfiguration.socketClockexec == true) flags |= transportSocketOptionSocketClockexec;
    if (serverConfiguration.socketReuseAddress == true) flags |= transportSocketOptionSocketReuseaddr;
    if (serverConfiguration.socketReusePort == true) flags |= transportSocketOptionSocketReuseport;
    if (serverConfiguration.socketReceiveBufferSize != null) {
      flags |= transportSocketOptionSocketRcvbuf;
      nativeServerConfiguration.ref.socket_receive_buffer_size = serverConfiguration.socketReceiveBufferSize!;
    }
    if (serverConfiguration.socketSendBufferSize != null) {
      flags |= transportSocketOptionSocketSndbuf;
      nativeServerConfiguration.ref.socket_send_buffer_size = serverConfiguration.socketSendBufferSize!;
    }
    if (serverConfiguration.socketReceiveLowAt != null) {
      flags |= transportSocketOptionSocketRcvlowat;
      nativeServerConfiguration.ref.socket_receive_low_at = serverConfiguration.socketReceiveLowAt!;
    }
    if (serverConfiguration.socketSendLowAt != null) {
      flags |= transportSocketOptionSocketSndlowat;
      nativeServerConfiguration.ref.socket_send_low_at = serverConfiguration.socketSendLowAt!;
    }
    nativeServerConfiguration.ref.socket_configuration_flags = flags;
    return nativeServerConfiguration;
  }
}
