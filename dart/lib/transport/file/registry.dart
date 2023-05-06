import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../bindings.dart';
import '../buffers.dart';
import '../callbacks.dart';
import '../channel.dart';
import '../constants.dart';
import '../links.dart';
import '../payload.dart';
import 'file.dart';

const _optionRdonly = 00;
const _optionWronly = 01;
const _optionRdwr = 02;
const _optionCreat = 0100;
const _optionTrunc = 01000;
const _optionAppend = 02000;

class TransportFileRegistry {
  final TransportBindings _bindings;
  final TransportCallbacks _callbacks;
  final Pointer<transport_worker_t> _workerPointer;
  final TransportBuffers _buffers;
  final TransportLinks _links;
  final TransportPayloadPool _payloadPool;

  final _files = <int, TransportFile>{};

  @visibleForTesting
  Map<int, TransportFile> get files => _files;

  TransportFileRegistry(this._bindings, this._callbacks, this._workerPointer, this._buffers, this._payloadPool, this._links);

  TransportFile? get(int fd) => _files[fd];

  TransportFile open(String path, {TransportFileMode mode = TransportFileMode.readWriteAppend, bool create = false, bool truncate = false, int permissions = 0}) {
    int options = 0;
    switch (mode) {
      case TransportFileMode.readOnly:
        options = _optionRdonly;
        break;
      case TransportFileMode.writeOnly:
        options = _optionWronly;
        break;
      case TransportFileMode.readWrite:
        options = _optionRdwr;
        break;
      case TransportFileMode.writeOnlyAppend:
        options = _optionWronly | _optionAppend;
        break;
      case TransportFileMode.readWriteAppend:
        options = _optionRdwr | _optionAppend;
        break;
    }
    if (truncate) options |= _optionTrunc;
    if (create) options |= _optionCreat;
    final fd = using((Arena arena) => _bindings.transport_file_open(path.toNativeUtf8(allocator: arena).cast(), options, permissions));
    final file = TransportFile(
      path,
      fd,
      _bindings,
      _workerPointer,
      _callbacks,
      TransportChannel(_workerPointer, fd, _bindings, _buffers),
      _buffers,
      _links,
      _payloadPool,
      this,
    );
    _files[fd] = file;
    return file;
  }

  Future<void> close({Duration? gracefulDuration}) => Future.wait(_files.values.toList().map((file) => file.close(gracefulDuration: gracefulDuration)));

  void remove(int fd) => _files.remove(fd);
}
