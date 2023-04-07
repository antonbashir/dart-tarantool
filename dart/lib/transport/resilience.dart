import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import 'package:iouring_transport/transport/extensions.dart';

import 'constants.dart';

import 'bindings.dart';
import 'callbacks.dart';
import 'client.dart';
import 'exception.dart';
import 'server.dart';

class ErrorHandler {
  final TransportServerRegistry _serverRegistry;
  final TransportClientRegistry _clientRegistry;
  final TransportBindings _bindings;
  final Pointer<transport_worker_t> _inboundWorkerPointer;
  final Pointer<transport_worker_t> _outboundWorkerPointer;
  final Pointer<Int64> _inboundUsedBuffers;
  final Pointer<Int64> _outboundUsedBuffers;
  final Queue<Completer<int>> _inboundBufferFinalizers;
  final Queue<Completer<int>> _outboundBufferFinalizers;
  final TransportCallbacks _callbacks;

  ErrorHandler(
    this._serverRegistry,
    this._clientRegistry,
    this._bindings,
    this._inboundWorkerPointer,
    this._outboundWorkerPointer,
    this._inboundUsedBuffers,
    this._outboundUsedBuffers,
    this._inboundBufferFinalizers,
    this._outboundBufferFinalizers,
    this._callbacks,
  );

  Future<int> _allocateInbound() async {
    var bufferId = _bindings.transport_worker_select_buffer(_inboundWorkerPointer);
    while (bufferId == -1) {
      final completer = Completer<int>();
      _inboundBufferFinalizers.add(completer);
      bufferId = await completer.future;
      if (_inboundUsedBuffers[bufferId] == transportBufferAvailable) return bufferId;
      bufferId = _bindings.transport_worker_select_buffer(_inboundWorkerPointer);
    }
    return bufferId;
  }

  void _releaseInboundBuffer(int bufferId) {
    _bindings.transport_worker_release_buffer(_inboundWorkerPointer, bufferId);
    if (_inboundBufferFinalizers.isNotEmpty) _inboundBufferFinalizers.removeLast().complete(bufferId);
  }

  void _releaseOutboundBuffer(int bufferId) {
    _bindings.transport_worker_release_buffer(_outboundWorkerPointer, bufferId);
    if (_outboundBufferFinalizers.isNotEmpty) _outboundBufferFinalizers.removeLast().complete(bufferId);
  }

  bool _ensureServerIsActive(TransportServer? server, int? bufferId, int? clientFd) {
    if (server == null) {
      if (bufferId != null) _releaseInboundBuffer(bufferId);
      if (clientFd != null) _serverRegistry.removeClient(clientFd);
      return false;
    }
    if (!server.active) {
      if (bufferId != null) _releaseInboundBuffer(bufferId);
      if (clientFd != null) _serverRegistry.removeClient(clientFd);
      _serverRegistry.removeServer(server.fd);
      return false;
    }
    return true;
  }

  bool _ensureClientIsActive(TransportClient? client, int? bufferId, int fd) {
    if (client == null) {
      if (bufferId != null) _releaseOutboundBuffer(bufferId);
      return false;
    }
    if (!client.active) {
      if (bufferId != null) _releaseOutboundBuffer(bufferId);
      _clientRegistry.removeClient(fd);
      return false;
    }
    return true;
  }

  void _handleReadWrite(int bufferId, int fd, int event, int result) {
    final server = _serverRegistry.getByClient(fd);
    if (!_ensureServerIsActive(server, bufferId, fd)) return;
    if (!server!.controller.hasListener) {
      _releaseInboundBuffer(bufferId);
      _bindings.transport_close_descritor(fd);
      _serverRegistry.removeClient(fd);
      return;
    }
    _releaseInboundBuffer(bufferId);
    _bindings.transport_close_descritor(fd);
    _serverRegistry.removeClient(fd);
    server.controller.addError(TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd));
  }

  void _handleReceiveMessage(int bufferId, int fd, int event, int result) {
    final server = _serverRegistry.getByServer(fd);
    if (!_ensureServerIsActive(server, bufferId, null)) return;
    _allocateInbound().then((newBufferId) {
      _bindings.transport_worker_receive_message(
        _inboundWorkerPointer,
        fd,
        newBufferId,
        server!.pointer.ref.family,
        MSG_TRUNC,
        transportEventReceiveMessage,
      );
    });
    if (!server!.controller.hasListener) {
      _releaseInboundBuffer(bufferId);
      return;
    }
    _releaseInboundBuffer(bufferId);
    server.controller.addError(TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd));
  }

  void _handleSendMessage(int bufferId, int fd, int event, int result) {
    final server = _serverRegistry.getByServer(fd);
    if (!_ensureServerIsActive(server, bufferId, null)) return;
    _releaseInboundBuffer(bufferId);
    server!.controller.addError(TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd));
  }

  void _handleAccept(int fd) {
    final server = _serverRegistry.getByServer(fd);
    if (!_ensureServerIsActive(server, null, null)) return;
    _bindings.transport_worker_accept(_inboundWorkerPointer, server!.pointer);
  }

  void _handleConnect(int fd, int event, int result) {
    final client = _clientRegistry.get(fd);
    if (!_ensureClientIsActive(client, null, fd)) {
      _callbacks.notifyConnectError(fd, TransportClosedException.forClient());
      client!.onComplete();
      return;
    }
    _clientRegistry.removeClient(fd);
    _callbacks.notifyConnectError(
      fd,
      TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd),
    );
    client!.onComplete();
  }

  void _handleReadReceiveCallbacks(int bufferId, int fd, int event, int result) {
    final client = _clientRegistry.get(fd);
    if (!_ensureClientIsActive(client, bufferId, fd)) {
      _callbacks.notifyReadError(bufferId, TransportClosedException.forClient());
      client!.onComplete();
      return;
    }
    _releaseOutboundBuffer(bufferId);
    _clientRegistry.removeClient(fd);
    _callbacks.notifyReadError(
      bufferId,
      TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd, bufferId: bufferId),
    );
    client!.onComplete();
  }

  void _handleWriteSendCallbacks(int bufferId, int fd, int event, int result) {
    final client = _clientRegistry.get(fd);
    if (!_ensureClientIsActive(client, bufferId, fd)) {
      _callbacks.notifyWriteError(bufferId, TransportClosedException.forClient());
      client!.onComplete();
      return;
    }
    _releaseOutboundBuffer(bufferId);
    _clientRegistry.removeClient(fd);
    _callbacks.notifyWriteError(
      bufferId,
      TransportException.forEvent(event, result, result.kernelErrorToString(_bindings), fd, bufferId: bufferId),
    );
    client!.onComplete();
  }

  void handle(int result, int data, int fd, int event) {
    switch (event) {
      case transportEventRead:
      case transportEventWrite:
        _handleReadWrite(((data >> 16) & 0xffff), fd, event, result);
        return;
      case transportEventReceiveMessage:
        _handleReceiveMessage(((data >> 16) & 0xffff), fd, event, result);
        return;
      case transportEventSendMessage:
        _handleSendMessage(((data >> 16) & 0xffff), fd, event, result);
        return;
      case transportEventAccept:
        _handleAccept(fd);
        return;
      case transportEventConnect:
        _handleConnect(fd, event, result);
        return;
      case transportEventReadCallback:
      case transportEventReceiveMessageCallback:
        _handleReadReceiveCallbacks(((data >> 16) & 0xffff), fd, event, result);
        return;
      case transportEventWriteCallback:
      case transportEventSendMessageCallback:
        _handleWriteSendCallbacks(((data >> 16) & 0xffff), fd, event, result);
        return;
    }
  }
}
