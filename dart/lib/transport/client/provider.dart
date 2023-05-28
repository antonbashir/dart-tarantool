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

  Future<void> read() => _client.read();

  Stream<TransportPayload> stream() {
    final out = StreamController<TransportPayload>(sync: true);
    out.onListen = () => unawaited(_client.read().onError((error, stackTrace) => out.addError(error!)));
    _client.inbound.listen(
      (event) {
        out.add(event);
        if (_client.active) unawaited(_client.read().onError((error, stackTrace) => out.addError(error!)));
      },
      onDone: out.close,
      onError: out.addError,
    );
    return out.stream;
  }

  void writeSingle(Uint8List bytes, {TransportRetryConfiguration? retry, void Function(Exception error)? onError, void Function()? onDone}) {
    if (retry == null) {
      unawaited(_client.writeSingle(bytes, onError: onError, onDone: onDone).onError((error, stackTrace) => onError?.call(error as Exception)));
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
        unawaited(_client.writeSingle(bytes, onError: _onError, onDone: onDone).onError((error, stackTrace) => onError?.call(error as Exception)));
      }));
    }

    unawaited(_client.writeSingle(bytes, onError: _onError, onDone: onDone).onError((error, stackTrace) => onError?.call(error as Exception)));
  }

  void writeMany(List<Uint8List> bytes, {TransportRetryConfiguration? retry, void Function(Exception error)? onError, void Function()? onDone}) {
    if (retry == null) {
      var doneCounter = 0;
      unawaited(_client.writeMany(bytes, onError: onError, onDone: () {
        if (++doneCounter == bytes.length) onDone?.call();
      }).onError((error, stackTrace) => onError?.call(error as Exception)));
      return;
    }

    var doneCounter = 0;
    var errorCounter = 0;
    var attempt = 0;

    void _onError(Exception error) {
      if (++errorCounter + doneCounter == bytes.length) {
        errorCounter = 0;
        if (!retry.predicate(error)) {
          onError?.call(error);
          return;
        }
        if (++attempt == retry.maxAttempts) {
          onError?.call(error);
          return;
        }
        unawaited(Future.delayed(retry.options.delay(attempt), () {
          unawaited(_client.writeMany(bytes.sublist(doneCounter), onError: _onError, onDone: () {
            if (++doneCounter == bytes.length) onDone?.call();
          }).onError((error, stackTrace) => onError?.call(error as Exception)));
        }));
      }
    }

    unawaited(_client.writeMany(bytes, onError: _onError, onDone: () {
      if (++doneCounter == bytes.length) onDone?.call();
    }).onError((error, stackTrace) => onError?.call(error as Exception)));
  }

  @pragma(preferInlinePragma)
  Future<void> close({Duration? gracefulDuration}) => _client.close(gracefulDuration: gracefulDuration);
}

class TransportDatagramClient {
  final TransportClientChannel _client;

  const TransportDatagramClient(this._client);

  bool get active => _client.active;
  Stream<TransportPayload> get inbound => _client.inbound;

  Future<void> receive({int? flags}) => _client.receive(flags: flags);

  Stream<TransportPayload> stream({int? flags}) {
    final out = StreamController<TransportPayload>(sync: true);
    out.onListen = () => unawaited(_client.receive(flags: flags).onError((error, stackTrace) => out.addError(error!)));
    _client.inbound.listen(
      (event) {
        out.add(event);
        if (_client.active) unawaited(_client.receive(flags: flags).onError((error, stackTrace) => out.addError(error!)));
      },
      onDone: out.close,
      onError: (error) {
        out.addError(error);
        if (_client.active) unawaited(_client.receive(flags: flags).onError((error, stackTrace) => out.addError(error!)));
      },
    );
    return out.stream;
  }

  void send(
    Uint8List bytes, {
    TransportRetryConfiguration? retry,
    int? flags,
    void Function(Exception error)? onError,
    void Function()? onDone,
  }) {
    if (retry == null) {
      unawaited(_client.send(bytes, onError: onError, onDone: onDone, flags: flags).onError((error, stackTrace) => onError?.call(error as Exception)));
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
        unawaited(_client.send(bytes, onError: _onError, onDone: onDone, flags: flags).onError((error, stackTrace) => onError?.call(error as Exception)));
      }));
    }

    unawaited(_client.send(bytes, onError: _onError, onDone: onDone, flags: flags).onError((error, stackTrace) => onError?.call(error as Exception)));
  }

  @pragma(preferInlinePragma)
  Future<void> close({Duration? gracefulDuration}) => _client.close(gracefulDuration: gracefulDuration);
}
