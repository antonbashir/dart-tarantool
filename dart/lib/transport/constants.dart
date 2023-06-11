import 'bindings.dart';
import 'exception.dart';

const preferInlinePragma = "vm:prefer-inline";

const empty = "";
const unknown = "unknown";
const newLine = "\n";
const slash = "/";
const dot = ".";
const star = "*";
const equalSpaced = " = ";
const openingBracket = "{";
const closingBracket = "}";
const comma = ",";
const parentDirectorySymbol = '..';
const currentDirectorySymbol = './';

const transportLibraryName = "libtransport.so";
const transportPackageName = "iouring_transport";

const packageConfigJsonFile = "package_config.json";

String loadError(path) => "Unable to load library ${path}";

const unableToFindProjectRoot = "Unable to find project root";

const pubspecYamlFile = 'pubspec.yaml';
const pubspecYmlFile = 'pubspec.yml';

class Directories {
  const Directories._();

  static const native = "/native";
  static const package = "/package";
  static const dotDartTool = ".dart_tool";
}

class Messages {
  const Messages._();

  static const runPubGet = "Run 'dart pub get'";
  static const specifyDartEntryPoint = 'Specify dart execution entry point';
  static const projectRootNotFound = "Project root not found (parent of 'pubspec.yaml')";
  static const nativeSourcesNotFound = "Native root does not contain any *.c or *.cpp sources";
}

class PackageConfigFields {
  PackageConfigFields._();

  static const rootUri = 'rootUri';
  static const name = 'name';
  static const packages = 'packages';
}

const transportBufferUsed = -1;

const transportEventRead = 1 << 0;
const transportEventWrite = 1 << 1;
const transportEventReceiveMessage = 1 << 2;
const transportEventSendMessage = 1 << 3;
const transportEventAccept = 1 << 4;
const transportEventConnect = 1 << 5;
const transportEventClient = 1 << 6;
const transportEventFile = 1 << 7;
const transportEventServer = 1 << 8;

const transportEventAll = transportEventRead |
    transportEventWrite |
    transportEventAccept |
    transportEventConnect |
    transportEventReceiveMessage |
    transportEventSendMessage |
    transportEventClient |
    transportEventFile |
    transportEventServer;

const ringSetupIopoll = 1 << 0;
const ringSetupSqpoll = 1 << 1;
const ringSetupSqAff = 1 << 2;
const ringSetupCqsize = 1 << 3;
const ringSetupClamp = 1 << 4;
const ringSetupAttachWq = 1 << 5;
const ringSetupRDisabled = 1 << 6;
const ringSetupSubmitAll = 1 << 7;
const ringSetupCoopTaskrun = 1 << 8;
const ringSetupTaskrunFlag = 1 << 9;
const ringSetupSqe128 = 1 << 10;
const ringSetupCqe32 = 1 << 11;
const ringSetupSingleIssuer = 1 << 12;
const ringSetupDeferTaskrun = 1 << 13;

const transportSocketOptionSocketNonblock = 1 << 1;
const transportSocketOptionSocketClockexec = 1 << 2;
const transportSocketOptionSocketReuseaddr = 1 << 3;
const transportSocketOptionSocketReuseport = 1 << 4;
const transportSocketOptionSocketRcvbuf = 1 << 5;
const transportSocketOptionSocketSndbuf = 1 << 6;
const transportSocketOptionSocketBroadcast = 1 << 7;
const transportSocketOptionSocketKeepalive = 1 << 8;
const transportSocketOptionSocketRcvlowat = 1 << 9;
const transportSocketOptionSocketSndlowat = 1 << 10;
const transportSocketOptionIpTtl = 1 << 11;
const transportSocketOptionIpAddMembership = 1 << 12;
const transportSocketOptionIpAddSourceMembership = 1 << 13;
const transportSocketOptionIpDropMembership = 1 << 14;
const transportSocketOptionIpDropSourceMembership = 1 << 15;
const transportSocketOptionIpFreebind = 1 << 16;
const transportSocketOptionIpMulticastAll = 1 << 17;
const transportSocketOptionIpMulticastIf = 1 << 18;
const transportSocketOptionIpMulticastLoop = 1 << 19;
const transportSocketOptionIpMulticastTtl = 1 << 20;
const transportSocketOptionTcpQuickack = 1 << 21;
const transportSocketOptionTcpDeferAccept = 1 << 22;
const transportSocketOptionTcpFastopen = 1 << 23;
const transportSocketOptionTcpKeepidle = 1 << 24;
const transportSocketOptionTcpKeepcnt = 1 << 25;
const transportSocketOptionTcpKeepintvl = 1 << 26;
const transportSocketOptionTcpMaxseg = 1 << 27;
const transportSocketOptionTcpNoDelay = 1 << 28;
const transportSocketOptionTcpSyncnt = 1 << 29;

const transportTimeoutInfinity = -1;
const transportParentRingNone = -1;

const transportIosqeFixedFile = 1 << 0;
const transportIosqeIoDrain = 1 << 1;
const transportIosqeIoLink = 1 << 2;
const transportIosqeIoHardlink = 1 << 3;
const transportIosqeAsync = 1 << 4;
const transportIosqeBufferSelect = 1 << 5;
const transportIosqeCqeSkipSuccess = 1 << 6;

enum TransportDatagramMessageFlag {
  oob(0x01),
  peek(0x02),
  dontroute(0x04),
  tryhard(0x04),
  ctrunc(0x08),
  proxy(0x10),
  trunc(0x20),
  dontwait(0x40),
  eor(0x80),
  waitall(0x100),
  fin(0x200),
  syn(0x400),
  confirm(0x800),
  rst(0x1000),
  errqueue(0x2000),
  nosignal(0x4000),
  more(0x8000),
  waitforone(0x10000),
  batch(0x40000),
  zerocopy(0x4000000),
  fastopen(0x20000000),
  cmsgCloexec(0x40000000);

  final int flag;

  const TransportDatagramMessageFlag(this.flag);
}

enum TransportEvent {
  accept,
  connect,
  serverRead,
  serverWrite,
  clientRead,
  clientWrite,
  serverReceive,
  serverSend,
  clientReceive,
  clientSend,
  fileRead,
  fileWrite,
  unknown;

  static TransportEvent serverEvent(int event) {
    if (event == transportEventRead) return TransportEvent.serverRead;
    if (event == transportEventWrite) return TransportEvent.serverWrite;
    if (event == transportEventSendMessage) return TransportEvent.serverSend;
    if (event == transportEventReceiveMessage) return TransportEvent.serverReceive;
    if (event == transportEventAccept) return TransportEvent.accept;
    return TransportEvent.unknown;
  }

  static TransportEvent fileEvent(int event) {
    if (event == transportEventRead) return TransportEvent.fileRead;
    if (event == transportEventWrite) return TransportEvent.fileWrite;
    return TransportEvent.unknown;
  }

  static TransportEvent clientEvent(int event) {
    if (event == transportEventRead) return TransportEvent.clientRead;
    if (event == transportEventWrite) return TransportEvent.clientWrite;
    if (event == transportEventSendMessage) return TransportEvent.clientSend;
    if (event == transportEventReceiveMessage) return TransportEvent.clientReceive;
    if (event == transportEventConnect) return TransportEvent.connect;
    return TransportEvent.unknown;
  }

  @override
  String toString() => name;
}

const transportRetryableErrorCodes = {EINTR, EAGAIN, ECANCELED};

enum TransportFileMode {
  readOnly(1 << 0),
  writeOnly(1 << 1),
  readWrite(1 << 2),
  writeOnlyAppend(1 << 3),
  readWriteAppend(1 << 4);

  final int mode;

  const TransportFileMode(this.mode);
}

class TransportMessages {
  TransportMessages._();

  static final workerMemory = "[worker] out of memory";
  static workerError(int result, TransportBindings bindings) => "[worker] code = $result, message = ${kernelErrorToString(result, bindings)}";
  static workerTrace(int id, int result, int data, int fd) => "worker = $id, result = $result,  bid = ${((data >> 16) & 0xffff)}, fd = $fd";
}
