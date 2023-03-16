import 'dart:convert';
import 'dart:io';

import 'package:iouring_transport/transport/defaults.dart';
import 'package:iouring_transport/transport/transport.dart';
import 'package:test/test.dart';

final Transport _transport = Transport(
  TransportDefaults.transport(),
  TransportDefaults.acceptor(),
  TransportDefaults.channel(),
  TransportDefaults.connector(),
);

void main() {
  test("simple", () async {
    final loop = await _transport.run();
    loop.serve("0.0.0.0", 12345, onAccept: (channel, descriptor) {
      _transport.logger.info("Accepted: $descriptor");
      channel.read(descriptor);
    }).listen((event) {
      final request = Utf8Decoder().convert(event.bytes);
      _transport.logger.info("Recevied: '$request'");
      event.respond(Utf8Encoder().convert("$request, world"));
    });
    await loop.awaitServer();
    _transport.logger.info("Served");
    final connector = await loop.provider.connector.connect("127.0.0.1", 12345);
    await connector.select().write(Utf8Encoder().convert("Hello"));
    _transport.logger.info("Sent: 'Hello'");
    final response = await connector.select().read();
    final responseMessage = Utf8Decoder().convert(response.release());
    _transport.logger.info("Responded: '$responseMessage'");
    expect(responseMessage, "Hello, world");
    exit(0);
  });
}
