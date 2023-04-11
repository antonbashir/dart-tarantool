import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'channels.dart';
import 'configuration.dart';
import 'constants.dart';
import 'defaults.dart';
import 'exception.dart';
import 'payload.dart';
import 'retry.dart';
import 'state.dart';

class TransportCommunicator {
  final TransportClient _client;

  TransportCommunicator(this._client);

  Future<TransportOutboundPayload> read() => _client.read();

  Future<void> write(Uint8List bytes) => _client.write(bytes);

  Future<TransportOutboundPayload> receiveMessage() => _client.receiveMessage();

  Future<void> sendMessage(Uint8List bytes) => _client.sendMessage(bytes);

  Future<void> close() => _client.close();
}

class TransportClient {
  final TransportEventStates _eventStates;
  final Pointer<transport_client_t> pointer;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportOutboundChannel _channel;
  final TransportBindings _bindings;
  final TransportRetryConfiguration retry;
  final int connectTimeout;
  final int readTimeout;
  final int writeTimeout;

  var _active = true;
  bool get active => _active;
  final _closer = Completer();

  var _pending = 0;

  TransportClient(
    this._eventStates,
    this._channel,
    this.pointer,
    this._workerPointer,
    this._bindings,
    this.retry,
    this.connectTimeout,
    this.readTimeout,
    this.writeTimeout,
  );

  Future<TransportOutboundPayload> read() async {
    final bufferId = await _channel.allocate();
    if (!_active) throw TransportClosedException.forClient();
    final completer = Completer<TransportOutboundPayload>();
    _eventStates.setOutboundReadCallback(bufferId, completer, TransportRetryState(retry, 0));
    _channel.read(bufferId, readTimeout, offset: 0);
    _pending++;
    return completer.future;
  }

  Future<void> write(Uint8List bytes) async {
    final bufferId = await _channel.allocate();
    if (!_active) throw TransportClosedException.forClient();
    final completer = Completer<void>();
    _eventStates.setOutboundWriteCallback(bufferId, completer, TransportRetryState(retry, 0));
    _channel.write(bytes, bufferId, writeTimeout);
    _pending++;
    return completer.future;
  }

  Future<TransportOutboundPayload> receiveMessage() async {
    final bufferId = await _channel.allocate();
    if (!_active) throw TransportClosedException.forClient();
    final completer = Completer<TransportOutboundPayload>();
    _eventStates.setOutboundReadCallback(bufferId, completer, TransportRetryState(retry, 0));
    _channel.receiveMessage(bufferId, pointer, readTimeout);
    _pending++;
    return completer.future;
  }

  Future<void> sendMessage(Uint8List bytes) async {
    final bufferId = await _channel.allocate();
    if (!_active) throw TransportClosedException.forClient();
    final completer = Completer<void>();
    _eventStates.setOutboundWriteCallback(bufferId, completer, TransportRetryState(retry, 0));
    _channel.sendMessage(bytes, bufferId, pointer, writeTimeout);
    _pending++;
    return completer.future;
  }

  Future<TransportClient> connect(Pointer<transport_worker_t> workerPointer) {
    final completer = Completer<TransportClient>();
    _eventStates.setConnectCallback(pointer.ref.fd, completer, TransportRetryState(retry, 0));
    _bindings.transport_worker_connect(workerPointer, pointer, connectTimeout);
    _pending++;
    return completer.future;
  }

  @pragma(preferInlinePragma)
  void onComplete() {
    _pending--;
    if (!_active && _pending == 0) _closer.complete();
  }

  Future<void> close() async {
    if (_active) {
      _active = false;
      _bindings.transport_worker_cancel(_workerPointer);
      if (_pending > 0) await _closer.future;
      _channel.close();
      _bindings.transport_client_destroy(pointer);
    }
  }
}

class TransportCommunicators {
  final List<TransportCommunicator> _communicators;
  var _next = 0;

  TransportCommunicators(this._communicators);

  TransportCommunicator select() {
    final client = _communicators[_next];
    if (++_next == _communicators.length) _next = 0;
    return client;
  }

  void forEach(FutureOr<void> Function(TransportCommunicator communicator) action) => _communicators.forEach(action);

  Iterable<Future<M>> map<M>(Future<M> Function(TransportCommunicator communicator) mapper) => _communicators.map(mapper);
}

class TransportClientRegistry {
  final TransportBindings _bindings;
  final TransportEventStates _eventStates;
  final Pointer<transport_worker_t> _workerPointer;
  final Queue<Completer<int>> _bufferFinalizers;
  final _clients = <int, TransportClient>{};

  TransportClientRegistry(this._eventStates, this._workerPointer, this._bindings, this._bufferFinalizers);

  Future<TransportCommunicators> createTcp(String host, int port, {TransportTcpClientConfiguration? configuration}) async {
    final communicators = <Future<TransportCommunicator>>[];
    configuration = configuration ?? TransportDefaults.tcpClient();
    for (var clientIndex = 0; clientIndex < configuration.pool; clientIndex++) {
      final clientPointer = using((arena) => _bindings.transport_client_initialize_tcp(
            _tcpConfiguration(configuration!, arena),
            host.toNativeUtf8(allocator: arena).cast(),
            port,
          ));
      final client = TransportClient(
        _eventStates,
        TransportOutboundChannel(
          _workerPointer,
          clientPointer.ref.fd,
          _bindings,
          _bufferFinalizers,
        ),
        clientPointer,
        _workerPointer,
        _bindings,
        configuration.retryConfiguration,
        configuration.connectTimeout.inSeconds,
        configuration.readTimeout.inSeconds,
        configuration.writeTimeout.inSeconds,
      );
      _clients[clientPointer.ref.fd] = client;
      communicators.add(client.connect(_workerPointer).then((client) => TransportCommunicator(client)));
    }
    return TransportCommunicators(await Future.wait(communicators));
  }

  Future<TransportCommunicators> createUnixStream(String path, {TransportUnixStreamClientConfiguration? configuration}) async {
    final clients = <Future<TransportCommunicator>>[];
    configuration = configuration ?? TransportDefaults.unixStreamClient();
    for (var clientIndex = 0; clientIndex < configuration.pool; clientIndex++) {
      final clientPointer = using((arena) => _bindings.transport_client_initialize_unix_stream(
            _unixStreamConfiguration(configuration!, arena),
            path.toNativeUtf8(allocator: arena).cast(),
          ));
      final clinet = TransportClient(
        _eventStates,
        TransportOutboundChannel(
          _workerPointer,
          clientPointer.ref.fd,
          _bindings,
          _bufferFinalizers,
        ),
        clientPointer,
        _workerPointer,
        _bindings,
        configuration.retryConfiguration,
        configuration.connectTimeout.inSeconds,
        configuration.readTimeout.inSeconds,
        configuration.writeTimeout.inSeconds,
      );
      _clients[clientPointer.ref.fd] = clinet;
      clients.add(clinet.connect(_workerPointer).then((client) => TransportCommunicator(client)));
    }
    return TransportCommunicators(await Future.wait(clients));
  }

  TransportCommunicator createUdp(String sourceHost, int sourcePort, String destinationHost, int destinationPort, {TransportUdpClientConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.udpClient();
    final clientPointer = using(
      (arena) => _bindings.transport_client_initialize_udp(
        _udpConfiguration(configuration!, arena),
        destinationHost.toNativeUtf8(allocator: arena).cast(),
        destinationPort,
        sourceHost.toNativeUtf8(allocator: arena).cast(),
        sourcePort,
      ),
    );
    final client = TransportClient(
      _eventStates,
      TransportOutboundChannel(
        _workerPointer,
        clientPointer.ref.fd,
        _bindings,
        _bufferFinalizers,
      ),
      clientPointer,
      _workerPointer,
      _bindings,
      configuration.retryConfiguration,
      -1,
      configuration.readTimeout.inSeconds,
      configuration.writeTimeout.inSeconds,
    );
    _clients[clientPointer.ref.fd] = client;
    return TransportCommunicator(client);
  }

  TransportCommunicator createUnixDatagram(String sourcePath, String destinationPath, {TransportUnixDatagramClientConfiguration? configuration}) {
    configuration = configuration ?? TransportDefaults.unixDatagramClient();
    final clientPointer = using(
      (arena) => _bindings.transport_client_initialize_unix_dgram(
        _unixDatagramConfiguration(configuration!, arena),
        destinationPath.toNativeUtf8(allocator: arena).cast(),
        sourcePath.toNativeUtf8(allocator: arena).cast(),
      ),
    );
    final client = TransportClient(
      _eventStates,
      TransportOutboundChannel(
        _workerPointer,
        clientPointer.ref.fd,
        _bindings,
        _bufferFinalizers,
      ),
      clientPointer,
      _workerPointer,
      _bindings,
      configuration.retryConfiguration,
      -1,
      configuration.readTimeout.inSeconds,
      configuration.writeTimeout.inSeconds,
    );
    _clients[clientPointer.ref.fd] = client;
    return TransportCommunicator(client);
  }

  TransportClient? get(int fd) => _clients[fd];

  Future<void> close() async {
    await Future.wait(_clients.values.map((client) => client.close()));
    _clients.clear();
  }

  void removeClient(int fd) => _clients.remove(fd);

  Pointer<transport_client_configuration_t> _tcpConfiguration(TransportTcpClientConfiguration clientConfiguration, Allocator allocator) {
    final nativeClientConfiguration = allocator<transport_client_configuration_t>();
    nativeClientConfiguration.ref.receive_buffer_size = clientConfiguration.receiveBufferSize;
    nativeClientConfiguration.ref.send_buffer_size = clientConfiguration.sendBufferSize;
    return nativeClientConfiguration;
  }

  Pointer<transport_client_configuration_t> _udpConfiguration(TransportUdpClientConfiguration clientConfiguration, Allocator allocator) {
    final nativeClientConfiguration = allocator<transport_client_configuration_t>();
    nativeClientConfiguration.ref.receive_buffer_size = clientConfiguration.receiveBufferSize;
    nativeClientConfiguration.ref.send_buffer_size = clientConfiguration.sendBufferSize;
    return nativeClientConfiguration;
  }

  Pointer<transport_client_configuration_t> _unixStreamConfiguration(TransportUnixStreamClientConfiguration clientConfiguration, Allocator allocator) {
    final nativeClientConfiguration = allocator<transport_client_configuration_t>();
    nativeClientConfiguration.ref.receive_buffer_size = clientConfiguration.receiveBufferSize;
    nativeClientConfiguration.ref.send_buffer_size = clientConfiguration.sendBufferSize;
    return nativeClientConfiguration;
  }

  Pointer<transport_client_configuration_t> _unixDatagramConfiguration(TransportUnixDatagramClientConfiguration clientConfiguration, Allocator allocator) {
    final nativeClientConfiguration = allocator<transport_client_configuration_t>();
    nativeClientConfiguration.ref.receive_buffer_size = clientConfiguration.receiveBufferSize;
    nativeClientConfiguration.ref.send_buffer_size = clientConfiguration.sendBufferSize;
    return nativeClientConfiguration;
  }
}
