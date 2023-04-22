import 'dart:typed_data';

import '../channel.dart';
import '../constants.dart';
import '../exception.dart';
import '../payload.dart';
import 'server.dart';

class TransportServerConnection {
  final TransportServer _server;
  final TransportChannel _channel;

  TransportServerConnection(this._server, this._channel);

  @pragma(preferInlinePragma)
  Future<TransportPayload> read() => _server.read(_channel);

  @pragma(preferInlinePragma)
  Future<List<TransportPayload>> readBatch(int count) => _server.readBatch(_channel, count);

  @pragma(preferInlinePragma)
  Future<void> write(Uint8List bytes) => _server.write(bytes, _channel);

  @pragma(preferInlinePragma)
  Future<void> writeBatch(Iterable<Uint8List> bytes) => _server.writeBatch(bytes, _channel);

  void listen(void Function(TransportPayload paylad) listener, {void Function(dynamic error, StackTrace? stackTrace)? onError}) async {
    while (!_server.closing && _server.connectionIsActive(_channel.fd)) {
      await read().then(listener, onError: (error, stackTrace) {
        if (error is TransportClosedException) return;
        if (error is TransportZeroDataException) return;
        if (error is TransportInternalException && (transportRetryableErrorCodes.contains(error.code))) return;
        onError?.call(error, stackTrace);
      });
    }
  }

  void listenBatched(int count, void Function(TransportPayload paylad) listener, {void Function(dynamic error, StackTrace? stackTrace)? onError}) async {
    while (!_server.closing && _server.connectionIsActive(_channel.fd)) {
      await readBatch(count).then((fragments) => fragments.forEach(listener), onError: (error, stackTrace) {
        if (error is TransportClosedException) return;
        if (error is TransportZeroDataException) return;
        if (error is TransportInternalException && (transportRetryableErrorCodes.contains(error.code))) return;
        onError?.call(error, stackTrace);
      });
    }
  }

  @pragma(preferInlinePragma)
  Future<void> close() => _server.closeConnection(_channel.fd);
}
