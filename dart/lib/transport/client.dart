import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:iouring_transport/transport/loop.dart';

import 'bindings.dart';
import 'payload.dart';

class TransportClient {
  final TransportEventLoopCallbacks _callbacks;
  final TransportResourceChannel _channel;
  final TransportBindings _bindings;
  final int fd;

  TransportClient(this._callbacks, this._channel, this._bindings, this.fd);

  Future<TransportPayload> read() async {
    final completer = Completer<TransportPayload>();
    _callbacks.putRead(fd, completer);
    return _channel.read(fd).then((value) => completer.future);
  }

  Future<void> write(Uint8List bytes) async {
    final completer = Completer<void>();
    _callbacks.putWrite(fd, completer);
    return _channel.write(bytes, fd).then((value) => completer.future);
  }

  void close() => _bindings.transport_close_descritor(fd);
}

class TransportConnector {
  final TransportBindings _bindings;
  final TransportEventLoopCallbacks _callbacks;
  final Pointer<transport_channel_t> _channelPointer;
  final Pointer<transport_t> _transport;

  TransportConnector(this._callbacks, this._channelPointer, this._transport, this._bindings);

  Future<TransportClient> connect(String host, int port) async {
    final completer = Completer<TransportClient>();
    final fd = _bindings.transport_socket_create_client(
      _transport.ref.acceptor_configuration.ref.max_connections,
      _transport.ref.acceptor_configuration.ref.receive_buffer_size,
      _transport.ref.acceptor_configuration.ref.send_buffer_size,
    );
    _callbacks.putConnect(fd, completer);
    using((arena) => _bindings.transport_channel_connect(_channelPointer, fd, host.toNativeUtf8(allocator: arena).cast(), port));
    return completer.future;
  }
}
