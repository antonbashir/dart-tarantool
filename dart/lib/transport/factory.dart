import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:iouring_transport/transport/bindings.dart';
import 'package:iouring_transport/transport/callbacks.dart';
import 'package:iouring_transport/transport/file.dart';
import 'package:iouring_transport/transport/server.dart';
import 'package:iouring_transport/transport/worker.dart';

import 'channels.dart';
import 'client.dart';
import 'payload.dart';

class TransportServersFactory {
  final TransportServerRegistry _registry;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportBindings _bindings;
  final TransportWorker _worker;
  final Queue<Completer<int>> _bufferFinalizers;

  TransportServersFactory(
    this._registry,
    this._workerPointer,
    this._bindings,
    this._worker,
    this._bufferFinalizers,
  );

  void tcp(
    String host,
    int port,
    void Function(TransportInboundChannel channel) onAccept,
    void Function(Stream<TransportInboundPayload> stream) handler,
  ) {
    final server = _registry.createTcp(host, port);
    server.accept(_workerPointer, onAccept);
    handler(server.stream);
  }

  void udp(
    String host,
    int port,
    void Function(TransportInboundChannel channel) onCreate,
    void Function(Stream<TransportInboundPayload> stream) handler,
  ) {
    final server = _registry.createUdp(host, port);
    onCreate(TransportInboundChannel(
      _workerPointer,
      server.pointer.ref.fd,
      _bindings,
      _bufferFinalizers,
      _worker,
      server.pointer,
    ));
    handler(server.stream);
  }

  void unixStream(
    String path,
    void Function(TransportInboundChannel channel) onAccept,
    void Function(Stream<TransportInboundPayload> stream) handler,
  ) {
    final server = _registry.createUnixStream(path);
    server.accept(_workerPointer, onAccept);
    handler(server.stream);
  }

  void unixDatagram(
    String path,
    void Function(TransportInboundChannel channel) onCreate,
    void Function(Stream<TransportInboundPayload> stream) handler,
  ) {
    final server = _registry.createUnixDatagram(path);
    onCreate(TransportInboundChannel(
      _workerPointer,
      server.pointer.ref.fd,
      _bindings,
      _bufferFinalizers,
      _worker,
      server.pointer,
    ));
    handler(server.stream);
  }
}

class TransportClientsFactory {
  final TransportClientRegistry _registry;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportBindings _bindings;
  final TransportWorker _worker;
  final Queue<Completer<int>> _bufferFinalizers;

  TransportClientsFactory(
    this._registry,
    this._workerPointer,
    this._bindings,
    this._worker,
    this._bufferFinalizers,
  );

  Future<TransportClientPool> tcp(String host, int port, {int? pool}) => _registry.createTcp(host, port, pool: pool);

  TransportClient udp(String sourceHost, int sourcePort, String destinationHost, int destinationPort, {int? pool}) => _registry.createUdp(
        sourceHost,
        sourcePort,
        destinationHost,
        destinationPort,
      );

  Future<TransportClientPool> unixStream(String path, {int? pool}) => _registry.createUnixStream(path, pool: pool);

  TransportClient unixDatagram(String sourcePath, String destinationPath, {int? pool}) => _registry.createUnixDatagram(
        sourcePath,
        destinationPath,
      );
}

class TransportFilesFactory {
  final TransportCallbacks _callbacks;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportBindings _bindings;
  final TransportWorker _worker;
  final Queue<Completer<int>> _bufferFinalizers;

  TransportFilesFactory(
    this._workerPointer,
    this._bindings,
    this._worker,
    this._bufferFinalizers,
    this._callbacks,
  );

  TransportFile open(String path) {
    final fd = using((Arena arena) => _bindings.transport_file_open(path.toNativeUtf8(allocator: arena).cast()));
    return TransportFile(_callbacks, TransportOutboundChannel(_workerPointer, fd, _bindings, _bufferFinalizers, _worker));
  }
}
