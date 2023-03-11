import 'dart:ffi';
import 'dart:isolate';

import 'bindings.dart';

class TransportEvent {
  late int result;
  final void Function(TransportEvent event) callback;

  TransportEvent(this.callback);
}

class TransportEventLoop {
  final TransportBindings _bindings;

  late final RawReceivePort port;
  late final Pointer<transport_event_loop_t> pointer;

  TransportEventLoop(this._bindings) {
    port = RawReceivePort(_callback);
  }
  void start() {
    _bindings.transport_event_loop_start(pointer);
    port.close();
    Isolate.exit();
  }

  void stop() {
    _bindings.transport_event_loop_stop(pointer);
  }

  void _callback(dynamic event) {
    TransportEvent transportEvent = _bindings.Dart_HandleFromPersistent(event) as TransportEvent;
    _bindings.Dart_DeletePersistentHandle(event);
    transportEvent.callback(transportEvent);
  }
}
