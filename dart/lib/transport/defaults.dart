import 'package:iouring_transport/transport/configuration.dart';

class TransportDefaults {
  TransportDefaults._();

  static TransportConfiguration transport() => TransportConfiguration(
        ringSize: 8192,
        slabSize: 16 * 1024 * 1024,
        memoryQuota: 2 * 1024 * 1024 * 1024,
        slabAllocationMinimalObjectSize: 8,
        slabAllocationGranularity: 8,
        slabAllocationFactor: 1.05,
        logColored: true,
        logLevel: 0,
      );

  static TransportChannelConfiguration channel() => TransportChannelConfiguration(
        buffersCount: 8,
        ringSize: 8192,
        bufferShift: 12,
      );

  static TransportControllerConfiguration controller() => TransportControllerConfiguration(
        retryMaxCount: 5,
        internalRingSize: 33554432,
      );

  static TransportAcceptorConfiguration acceptor() => TransportAcceptorConfiguration(
        backlog: 512,
        ringSize: 2048,
      );

  static TransportConnectorConfiguration connector() => TransportConnectorConfiguration(
        ringSize: 2048,
      );
}
