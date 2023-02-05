import 'package:iouring_transport/transport/configuration.dart';

class TransportDefaults {
  TransportDefaults._();

  static TransportConfiguration transport() => TransportConfiguration(
        ringSize: 32768,
        slabSize: 16 * 1024 * 1024,
        memoryQuota: 2 * 1024 * 1024 * 1024,
        slabAllocationMinimalObjectSize: 8,
        slabAllocationGranularity: 8,
        slabAllocationFactor: 1.05,
      );

  static TransportChannelConfiguration channel() => TransportChannelConfiguration(
        bufferInitialCapacity: 16320,
        bufferLimit: 18 * 16320,
        bufferAvailableAwaitDelayed: Duration(seconds: 5),
        payloadBufferSize: 32,
      );

  static TransportControllerConfiguration controller() => TransportControllerConfiguration(
        cqesSize: 4096,
        batchMessageLimit: 2048,
        internalRingSize: 33554432,
      );

  static TransportConnectionConfiguration connection() => TransportConnectionConfiguration();
}
