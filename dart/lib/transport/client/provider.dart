import 'dart:async';
import 'dart:typed_data';

import '../configuration.dart';
import '../constants.dart';
import '../payload.dart';
import 'client.dart';

class TransportClientConnection {
  final TransportClientChannel _client;

  const TransportClientConnection(this._client);

  bool get active => _client.active;
  Stream<TransportPayload> get inbound => _client.inbound;

  @pragma(preferInlinePragma)
  Stream<TransportPayload> read() {
    unawaited(_client.read());
    return _client.inbound.map((event) {
      if (_client.active) unawaited(_client.read());
      return event;
    });
  }

  @pragma(preferInlinePragma)
  void writeSingle(Uint8List bytes, {TransportRetryConfiguration? retry, void Function(Exception error)? onError}) {
    if (retry == null) {
      unawaited(_client.writeSingle(bytes, onError: onError));
      return;
    }

    var attempt = 0;
    void _onError(Exception error) {
      if (!retry.predicate(error)) {
        onError?.call(error);
        return;
      }
      if (++attempt == retry.maxAttempts) {
        onError?.call(error);
        return;
      }
      unawaited(Future.delayed(retry.options.delay(attempt), () {
        unawaited(_client.writeSingle(bytes, onError: _onError));
      }));
    }

    unawaited(_client.writeSingle(bytes, onError: _onError));
  }

  @pragma(preferInlinePragma)
  void writeMany(List<Uint8List> bytes, {TransportRetryConfiguration? retry, void Function(Exception error)? onError}) {
    if (retry == null) {
      unawaited(_client.writeMany(bytes, onError: onError));
      return;
    }

    var attempt = 0;
    void _onError(Exception error) {
      if (!retry.predicate(error)) {
        onError?.call(error);
        return;
      }
      if (++attempt == retry.maxAttempts) {
        onError?.call(error);
        return;
      }
      unawaited(Future.delayed(retry.options.delay(attempt), () {
        unawaited(_client.writeMany(bytes, onError: _onError));
      }));
    }

    unawaited(_client.writeMany(bytes, onError: _onError));
  }

  @pragma(preferInlinePragma)
  Future<void> close({Duration? gracefulDuration}) => _client.close(gracefulDuration: gracefulDuration);
}

class TransportDatagramClient {
  final TransportClientChannel _client;

  const TransportDatagramClient(this._client);

  bool get active => _client.active;
  Stream<TransportPayload> get inbound => _client.inbound;

  @pragma(preferInlinePragma)
  Stream<TransportPayload> receive() {
    unawaited(_client.receive());
    return _client.inbound.map((event) {
      if (_client.active) unawaited(_client.receive());
      return event;
    }).handleError((error) {
      if (_client.active) {
        unawaited(_client.receive());
      }
      throw error;
    });
  }

  @pragma(preferInlinePragma)
  void send(Uint8List bytes, {TransportRetryConfiguration? retry, int? flags, void Function(Exception error)? onError}) {
    if (retry == null) {
      unawaited(_client.send(bytes, onError: onError));
      return;
    }

    var attempt = 0;
    void _onError(Exception error) {
      if (!retry.predicate(error)) {
        onError?.call(error);
        return;
      }
      if (++attempt == retry.maxAttempts) {
        onError?.call(error);
        return;
      }
      unawaited(Future.delayed(retry.options.delay(attempt), () {
        unawaited(_client.send(bytes, onError: _onError));
      }));
    }

    unawaited(_client.send(bytes, onError: _onError));
  }

  @pragma(preferInlinePragma)
  Future<void> close({Duration? gracefulDuration}) => _client.close(gracefulDuration: gracefulDuration);
}
