import 'configuration.dart';
import 'constants.dart';

class TransportDefaults {
  TransportDefaults._();

  static TransportConfiguration transport() => TransportConfiguration(
        logLevel: TransportLogLevel.debug,
        listenerIsolates: 2,
        workerInsolates: 4,
      );

  static TransportListenerConfiguration listener() => TransportListenerConfiguration(
        ringSize: 16384,
        ringFlags: ringSetupCoopTaskrun,
      );

  static TransportWorkerConfiguration worker() => TransportWorkerConfiguration(
        buffersCount: 2048,
        bufferSize: 4096,
        ringSize: 32768,
        ringFlags: ringSetupCoopTaskrun,
      );

  static TransportClientConfiguration client() => TransportClientConfiguration(
        maxConnections: 2048,
        receiveBufferSize: 2048,
        sendBufferSize: 2048,
        defaultPool: 1,
      );

  static TransportAcceptorConfiguration acceptor() => TransportAcceptorConfiguration(
        maxConnections: 2048,
        receiveBufferSize: 2048,
        sendBufferSize: 2048,
      );
}
