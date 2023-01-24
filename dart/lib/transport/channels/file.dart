import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:iouring_transport/transport/channels/channel.dart';

class TransportFileChannel {
  final TransportChannel _delegate;
  final _decoder = Utf8Decoder();
  final _encoder = Utf8Encoder();

  TransportFileChannel(this._delegate);

  void start() => _delegate.start();

  void stop() => _delegate.stop();

  bool get active => _delegate.active;

  Stream<Uint8List> get bytesOutput => _delegate.bytesOutput;

  Stream<String> get stringOutput => _delegate.stringOutput;

  Stream<Uint8List> get bytesInput => _delegate.bytesInput;

  Stream<String> get stringInput => _delegate.stringInput;

  Future<Uint8List> readBytes() async {
    Completer completer = Completer();
    final bytes = BytesBuilder();
    var offset = 0;
    queueRead();
    _delegate.bytesOutput.listen((data) {
      bytes.add(data);
      if (data.isEmpty || data.any((element) => element == 0)) {
        completer.complete();
        return;
      }
      queueRead(offset: offset += data.length);
    });
    await completer.future;
    return bytes.takeBytes();
  }

  Future<String> readString() => readBytes().then(_decoder.convert);

  Future<void> writeBytes(Uint8List bytes) async {
    Completer completer = Completer();
    var offset = 0;
    queueWriteBytes(bytes);
    _delegate.bytesInput.listen((data) {
      offset += data.length;
      if (data.isEmpty || offset >= bytes.length) {
        completer.complete();
        return;
      }
      queueWriteBytes(bytes, offset: offset);
    });
    await completer.future;
  }

  Future<void> writeString(String string) => writeBytes(_encoder.convert(string));

  void queueRead({int size = 64, int offset = 0}) => _delegate.queueRead(size: size, offset: offset);

  void queueWriteBytes(Uint8List bytes, {int size = 64, int offset = 0}) => _delegate.queueWriteBytes(bytes, size: size, offset: offset);

  void queueWriteString(String string, {int size = 64, int offset = 0}) => _delegate.queueWriteString(string, size: size, offset: offset);
}
