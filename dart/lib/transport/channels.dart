import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'bindings.dart';
import 'constants.dart';

class TransportChannel {
  static final _channels = <int, TransportChannel>{};

  final Pointer<transport_channel_t> pointer;
  final TransportBindings _bindings;
  late final StreamController<int> _availableBuffersController;
  late final Stream<int> _availableBuffers;

  TransportChannel(this.pointer, this._bindings) {
    _availableBuffersController = StreamController();
    _availableBuffers = _availableBuffersController.stream;
    _channels[pointer.address] = this;
  }

  @pragma(preferInlinePragma)
  Future<int> allocate() async {
    var bufferId = _bindings.transport_channel_allocate_buffer(pointer);
    if (bufferId == -1) {
      return _availableBuffers.last;
    }
    return bufferId;
  }

  @pragma(preferInlinePragma)
  void free(int bufferId) {
    pointer.ref.used_buffers[bufferId] = transportBufferAvailable;
    pointer.ref.used_buffers_offsets[bufferId] = 0;
    _availableBuffersController.add(bufferId);
  }

  @pragma(preferInlinePragma)
  static TransportChannel channel(int pointer) => _channels[pointer]!;
}

class TransportServerChannel extends TransportChannel {
  TransportServerChannel(super.pointer, super._bindings);

  void read(int fd, {int offset = 0}) {
    allocate().then((bufferId) => _bindings.transport_channel_read(pointer, fd, bufferId, offset, transportEventRead));
  }

  void write(Uint8List bytes, int fd, {int offset = 0}) {
    allocate().then((bufferId) {
      final buffer = pointer.ref.buffers[bufferId];
      buffer.iov_base.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
      buffer.iov_len = bytes.length;
      _bindings.transport_channel_write(pointer, fd, bufferId, offset, transportEventWrite);
    });
  }
}

class TransportResourceChannel extends TransportChannel {
  TransportResourceChannel(super.pointer, super._bindings);

  void read(int fd, int bufferId, {int offset = 0}) {
    _bindings.transport_channel_read(pointer, fd, bufferId, offset, transportEventReadCallback);
  }

  void write(Uint8List bytes, int fd, int bufferId, {int offset = 0}) {
    final buffer = pointer.ref.buffers[bufferId];
    buffer.iov_base.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    buffer.iov_len = bytes.length;
    _bindings.transport_channel_write(pointer, fd, bufferId, offset, transportEventWriteCallback);
  }
}
