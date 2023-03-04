class TransportConfiguration {
  final int ringSize;
  final int slabSize;
  final int memoryQuota;
  final int slabAllocationMinimalObjectSize;
  final int slabAllocationGranularity;
  final double slabAllocationFactor;
  final int logLevel;
  final bool logColored;

  TransportConfiguration({
    required this.ringSize,
    required this.slabSize,
    required this.memoryQuota,
    required this.slabAllocationMinimalObjectSize,
    required this.slabAllocationGranularity,
    required this.slabAllocationFactor,
    required this.logLevel,
    required this.logColored,
  });

  TransportConfiguration copyWith({
    int? ringSize,
    int? slabSize,
    int? memoryQuota,
    int? bufferInitialCapacity,
    int? bufferLimit,
    int? slabAllocationMinimalObjectSize,
    int? slabAllocationGranularity,
    double? slabAllocationFactor,
    int? logLevel,
    bool? logColored,
  }) =>
      TransportConfiguration(
        ringSize: ringSize ?? this.ringSize,
        slabSize: slabSize ?? this.slabSize,
        memoryQuota: memoryQuota ?? this.memoryQuota,
        slabAllocationMinimalObjectSize: slabAllocationMinimalObjectSize ?? this.slabAllocationMinimalObjectSize,
        slabAllocationGranularity: slabAllocationGranularity ?? this.slabAllocationGranularity,
        slabAllocationFactor: slabAllocationFactor ?? this.slabAllocationFactor,
        logColored: logColored ?? this.logColored,
        logLevel: logLevel ?? this.logLevel,
      );
}

class TransportChannelConfiguration {
  final int buffersCount;
  final int bufferSize;

  TransportChannelConfiguration({
    required this.buffersCount,
    required this.bufferSize,
  });

  TransportChannelConfiguration copyWith({
    int? buffersCount,
    int? ringSize,
    int? bufferSize,
  }) =>
      TransportChannelConfiguration(
        buffersCount: buffersCount ?? this.buffersCount,
        bufferSize: bufferSize ?? this.bufferSize,
      );
}


class TransportAcceptorConfiguration {
  final int backlog;
  final int ringSize;

  TransportAcceptorConfiguration({
    required this.backlog,
    required this.ringSize,
  });

  TransportAcceptorConfiguration copyWith({
    int? backlog,
    int? ringSize,
  }) =>
      TransportAcceptorConfiguration(backlog: backlog ?? this.backlog, ringSize: ringSize ?? this.ringSize);
}

class TransportConnectorConfiguration {
  final int ringSize;

  TransportConnectorConfiguration({
    required this.ringSize,
  });

  TransportConnectorConfiguration copyWith({
    int? ringSize,
  }) =>
      TransportConnectorConfiguration(ringSize: ringSize ?? this.ringSize);
}
