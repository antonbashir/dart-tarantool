import 'dart:io';

import '../constants.dart';
import 'provider.dart';
import 'registry.dart';
import 'package:meta/meta.dart';

class TransportFilesFactory {
  final TransportFileRegistry _registry;

  @visibleForTesting
  TransportFileRegistry get registry => _registry;

  TransportFilesFactory(this._registry);

  TransportFileProvider open(
    String path, {
    TransportFileMode mode = TransportFileMode.readWriteAppend,
    bool create = false,
    bool truncate = false,
  }) {
    final delegate = File(path);
    return TransportFileProvider(
      _registry.open(
        path,
        mode: mode,
        create: create && !delegate.existsSync(),
        truncate: truncate,
      ),
      delegate,
    );
  }
}
