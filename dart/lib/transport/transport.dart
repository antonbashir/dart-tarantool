import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:iouring_transport/transport/constants.dart';

import 'bindings.dart';
import 'configuration.dart';
import 'exception.dart';
import 'listener.dart';
import 'logger.dart';
import 'lookup.dart';

class Transport {
  final TransportConfiguration transportConfiguration;
  final TransportAcceptorConfiguration acceptorConfiguration;
  final TransportListenerConfiguration listenerConfiguration;
  final TransportWorkerConfiguration workerConfiguration;
  final TransportClientConfiguration clientConfiguration;
  late final TransportLogger logger;

  final _listenerExit = ReceivePort();
  final _workerExit = ReceivePort();

  late final String? _libraryPath;
  late final TransportBindings _bindings;
  late final TransportLibrary _library;
  late final Pointer<transport_t> _transport;

  Transport(this.transportConfiguration, this.acceptorConfiguration, this.listenerConfiguration, this.workerConfiguration, this.clientConfiguration, {String? libraryPath}) {
    this._libraryPath = libraryPath;

    _library = TransportLibrary.load(libraryPath: libraryPath);
    _bindings = TransportBindings(_library.library);

    logger = TransportLogger(transportConfiguration.logLevel);

    final nativeAcceptorConfiguration = calloc<transport_acceptor_configuration_t>();
    nativeAcceptorConfiguration.ref.max_connections = acceptorConfiguration.maxConnections;
    nativeAcceptorConfiguration.ref.receive_buffer_size = acceptorConfiguration.receiveBufferSize;
    nativeAcceptorConfiguration.ref.send_buffer_size = acceptorConfiguration.sendBufferSize;

    final nativeClientConfiguration = calloc<transport_client_configuration_t>();
    nativeClientConfiguration.ref.max_connections = clientConfiguration.maxConnections;
    nativeClientConfiguration.ref.receive_buffer_size = clientConfiguration.receiveBufferSize;
    nativeClientConfiguration.ref.send_buffer_size = clientConfiguration.sendBufferSize;

    final nativeListenerConfiguration = calloc<transport_listener_configuration_t>();
    nativeListenerConfiguration.ref.ring_flags = listenerConfiguration.ringFlags;
    nativeListenerConfiguration.ref.ring_size = listenerConfiguration.ringSize;
    nativeListenerConfiguration.ref.workers_count = transportConfiguration.workerInsolates;

    final nativeWorkerConfiguration = calloc<transport_worker_configuration_t>();
    nativeWorkerConfiguration.ref.ring_flags = workerConfiguration.ringFlags;
    nativeWorkerConfiguration.ref.ring_size = workerConfiguration.ringSize;
    nativeWorkerConfiguration.ref.buffer_size = workerConfiguration.bufferSize;
    nativeWorkerConfiguration.ref.buffers_count = workerConfiguration.buffersCount;

    _transport = _bindings.transport_initialize(
      nativeListenerConfiguration,
      nativeWorkerConfiguration,
      nativeClientConfiguration,
      nativeAcceptorConfiguration,
    );
  }

  Future<void> shutdown() async {
    await _listenerExit.take(transportConfiguration.listenerIsolates).toList();
    _bindings.transport_destroy(_transport);
    logger.info("[transport]: destroyed");
  }

  Future<void> serve(String host, int port, void Function(SendPort input) worker, {SendPort? receiver}) => _run(
        worker,
        acceptor: using((Arena arena) => _bindings.transport_acceptor_initialize(
              _transport.ref.acceptor_configuration,
              host.toNativeUtf8(allocator: arena).cast(),
              port,
            )),
        receiver: receiver,
      );

  Future<void> run(void Function(SendPort input) worker, {Pointer<transport_acceptor>? acceptor, SendPort? receiver}) => _run(worker, receiver: receiver);

  Future<void> _run(void Function(SendPort input) worker, {Pointer<transport_acceptor>? acceptor, SendPort? receiver}) async {
    final fromTransportToListener = ReceivePort();
    final fromTransportToWorker = ReceivePort();
    var listeners = 0;
    final listenerCompleter = Completer();
    final workersCompleter = Completer();
    final workerAddresses = <int>[];
    final workerMeessagePorts = <SendPort>[];
    final workerActivators = <SendPort>[];
    final workerPointers = <Pointer<transport_worker_t>>[];

    fromTransportToWorker.listen((ports) {
      SendPort toWorker = ports[0];
      workerMeessagePorts.add(ports[1]);
      workerActivators.add(ports[2]);
      final workerPointer = (workerConfiguration.ringFlags & ringSetupAttachWq != 0) && (workerConfiguration.ringFlags & ringSetupSqpoll != 0)
          ? _bindings.transport_worker_initialize(_transport.ref.worker_configuration, workerAddresses.length, workerPointers.isEmpty ? 0 : workerPointers[0].ref.ring_fd)
          : _bindings.transport_worker_initialize(_transport.ref.worker_configuration, workerAddresses.length, 0);
      workerPointers.add(workerPointer);
      if (workerPointer == nullptr) {
        listenerCompleter.completeError(TransportException("[worker] is null"));
        return;
      }
      workerAddresses.add(workerPointer.address);
      final workerInput = [
        _libraryPath,
        _transport.address,
        workerPointer.address,
        receiver,
      ];
      if (acceptor != null) workerInput.add(acceptor.address);
      toWorker.send(workerInput);
      if (workerAddresses.length == transportConfiguration.workerInsolates) {
        fromTransportToWorker.close();
        workersCompleter.complete();
      }
    });

    fromTransportToListener.listen((port) async {
      await workersCompleter.future;
      final listenerPointer = _bindings.transport_listener_initialize(_transport.ref.listener_configuration);
      if (listenerPointer == nullptr) {
        listenerCompleter.completeError(TransportException("[listener] is null"));
        fromTransportToListener.close();
        return;
      }
      for (var workerIndex = 0; workerIndex < transportConfiguration.workerInsolates; workerIndex++) {
        final worker = Pointer.fromAddress(workerAddresses[workerIndex]).cast<transport_worker_t>();
        _bindings.transport_listener_pool_add(worker.ref.listeners, listenerPointer);
      }
      (port as SendPort).send([
        _libraryPath,
        listenerPointer.address,
        listenerConfiguration.ringSize,
        workerMeessagePorts,
      ]);
      if (++listeners == transportConfiguration.listenerIsolates) {
        fromTransportToListener.close();
        listenerCompleter.complete();
      }
    });

    for (var isolate = 0; isolate < transportConfiguration.workerInsolates; isolate++) {
      Isolate.spawn<SendPort>(
        worker,
        fromTransportToWorker.sendPort,
        onExit: _workerExit.sendPort,
      );
    }

    for (var isolate = 0; isolate < transportConfiguration.listenerIsolates; isolate++) {
      Isolate.spawn<SendPort>(
        (toTransport) => TransportListener(toTransport).initialize(),
        fromTransportToListener.sendPort,
        onExit: _listenerExit.sendPort,
      );
    }

    await listenerCompleter.future;
    logger.info("[transport]: ready");
    workerActivators.forEach((port) => port.send(null));
  }
}
