import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:iouring_transport/transport/defaults.dart';
import 'package:iouring_transport/transport/transport.dart';
import 'package:iouring_transport/transport/worker.dart';
import 'package:test/test.dart';

import 'generators.dart';
import 'test.dart';
import 'validators.dart';

void testUnixStreamSingle({
  required int index,
  required int listeners,
  required int workers,
  required int clientsPool,
  required int listenerFlags,
  required int workerFlags,
}) {
  test("(single) [index = $index, listeners = $listeners, workers = $workers, clients = $clientsPool]", () async {
    final transport = Transport(
      TransportDefaults.transport().copyWith(listenerIsolates: listeners, workerInsolates: workers),
      TransportDefaults.listener().copyWith(ringFlags: listenerFlags),
      TransportDefaults.inbound().copyWith(ringFlags: workerFlags),
      TransportDefaults.outbound().copyWith(ringFlags: workerFlags),
    );
    final done = ReceivePort();
    await transport.run(transmitter: done.sendPort, (input) async {
      final worker = TransportWorker(input);
      await worker.initialize();
      final serverSocket = File(Directory.current.path + "/socket_${worker.id}.sock");
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      worker.servers.unixStream(
        serverSocket.path,
        (connection) => connection.listen(
          (event) {
            Validators.request(event.takeBytes());
            connection.writeSingle(Generators.response());
          },
        ),
      );
      final clients = await worker.clients.unixStream(serverSocket.path, configuration: TransportDefaults.unixStreamClient().copyWith(pool: clientsPool));
      final responses = await Future.wait(
        clients.map((client) => client.writeSingle(Generators.request()).then((_) => client.readSingle().then((value) => value.takeBytes()))).toList(),
      );
      responses.forEach(Validators.response);
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      worker.transmitter!.send(null);
    });
    await done.take(workers).toList();
    done.close();
    await transport.shutdown(gracefulDuration: Duration(milliseconds: 100));
  });
}

void testUnixStreamMany({
  required int index,
  required int listeners,
  required int workers,
  required int clientsPool,
  required int listenerFlags,
  required int workerFlags,
  required int count,
}) {
  test("(many) [index = $index, listeners = $listeners, workers = $workers, clients = $clientsPool, count = $count]", () async {
    final transport = Transport(
      TransportDefaults.transport().copyWith(listenerIsolates: listeners, workerInsolates: workers),
      TransportDefaults.listener().copyWith(ringFlags: listenerFlags),
      TransportDefaults.inbound().copyWith(ringFlags: workerFlags),
      TransportDefaults.outbound().copyWith(ringFlags: workerFlags),
    );
    final done = ReceivePort();
    await transport.run(transmitter: done.sendPort, (input) async {
      final worker = TransportWorker(input);
      await worker.initialize();
      final serverSocket = File(Directory.current.path + "/socket_${worker.id}.sock");
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      worker.servers.unixStream(
        serverSocket.path,
        (connection) {
          final serverResults = BytesBuilder();
          connection.listen(
            (event) {
              serverResults.add(event.takeBytes());
              if (serverResults.length == Generators.requestsSum(count).length) {
                Validators.requestsSum(serverResults.takeBytes(), count);
                connection.writeMany(Generators.responses(count));
              }
            },
          );
        },
      );
      final clients = await worker.clients.unixStream(serverSocket.path, configuration: TransportDefaults.unixStreamClient().copyWith(pool: clientsPool));
      await Future.wait(clients.map(
        (client) async {
          final clientResults = BytesBuilder();
          final completer = Completer();
          client.writeMany(Generators.requests(count)).then(
                (_) => client.listen(
                  (event) {
                    clientResults.add(event.takeBytes());
                    if (clientResults.length == Generators.responsesSum(count).length) completer.complete();
                  },
                ),
              );
          return completer.future.then((value) => Validators.responsesSum(clientResults.takeBytes(), count));
        },
      ));
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      worker.transmitter!.send(null);
    });
    await done.take(workers).toList();
    done.close();
    await transport.shutdown(gracefulDuration: Duration(milliseconds: 100));
  });
}

void testUnixDgram({
  required int index,
  required int listeners,
  required int workers,
  required int clients,
  required int listenerFlags,
  required int workerFlags,
}) {
  test("[index = $index, listeners = $listeners, workers = $workers, clients = $clients]", () async {
    final transport = Transport(
      TransportDefaults.transport().copyWith(listenerIsolates: listeners, workerInsolates: workers),
      TransportDefaults.listener().copyWith(ringFlags: listenerFlags),
      TransportDefaults.inbound().copyWith(ringFlags: workerFlags),
      TransportDefaults.outbound().copyWith(ringFlags: workerFlags),
    );
    final done = ReceivePort();
    final serverData = Utf8Encoder().convert("respond");
    await transport.run(transmitter: done.sendPort, (input) async {
      final clientData = Utf8Encoder().convert("request");
      final serverData = Utf8Encoder().convert("respond");
      final worker = TransportWorker(input);
      await worker.initialize();
      final serverSocket = File(Directory.current.path + "/socket_${worker.id}.sock");
      final clientSockets = List.generate(clients, (index) => File(Directory.current.path + "/socket_${worker.id}_$index.sock"));
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      clientSockets.where((socket) => socket.existsSync()).forEach((socket) => socket.deleteSync());
      worker.servers.unixDatagram(serverSocket.path).listen(
        onError: (error) => print(error),
        (event) {
          event.release();
          event.respondSingleMessage(serverData).then((value) => worker.transmitter!.send(serverData)).onError((error, stackTrace) => print(error));
        },
      );
      final responseFutures = <Future<List<int>>>[];
      for (var clientIndex = 0; clientIndex < clients; clientIndex++) {
        final client = worker.clients.unixDatagram(clientSockets[clientIndex].path, serverSocket.path);
        responseFutures.add(client.sendSingleMessage(clientData, retry: TransportDefaults.retry()).then((value) => client.receiveSingleMessage()).then((value) => value.takeBytes()));
      }
      final responses = await Future.wait(responseFutures);
      responses.forEach((response) => worker.transmitter!.send(response));
      if (serverSocket.existsSync()) serverSocket.deleteSync();
      clientSockets.where((socket) => socket.existsSync()).forEach((socket) => socket.deleteSync());
    });
    (await done.take(workers * clients * 2).toList()).forEach((response) => expect(response, serverData));
    done.close();
    await transport.shutdown();
  });
}
