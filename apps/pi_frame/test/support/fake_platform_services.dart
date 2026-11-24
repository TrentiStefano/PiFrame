import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:pi_frame/data/platform/drop_target_service.dart';
import 'package:pi_frame/data/platform/embedded_browser_service.dart';
import 'package:pi_frame/data/platform/file_dialog_service.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/http_service.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:pi_frame/data/platform/process_service.dart';
import 'package:pi_frame/data/platform/window_service.dart';

// Test doubles for the platform services in lib/data/platform. Each records
// what the feature asked for, so tests assert the interaction, not the plugin.

class FakeHostEnvironmentService implements HostEnvironmentService {
  FakeHostEnvironmentService({
    this.isWeb = false,
    this.isWindows = false,
    String? operatingSystem,
    Map<String, String> variables = const {},
  }) : operatingSystem = operatingSystem ?? (isWindows ? 'windows' : 'linux'),
       _variables = Map.of(variables);

  @override
  final bool isWeb;

  @override
  final bool isWindows;

  @override
  final String operatingSystem;

  final Map<String, String> _variables;

  @override
  String? variable(String name) => _variables[name];
}

class FakeLinkService implements LinkService {
  final List<Uri> opened = [];
  bool result = true;

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

class FakeFileDialogService implements FileDialogService {
  List<PickedFile> files = const [];
  String? directory;
  final List<List<String>> fileRequestedExtensions = [];
  final List<bool> fileRequestedMultiple = [];
  final List<String?> fileRequestedLabels = [];
  int directoryRequests = 0;

  @override
  Future<List<PickedFile>> pickFiles({String? label, List<String> extensions = const [], bool multiple = true}) async {
    fileRequestedLabels.add(label);
    fileRequestedExtensions.add(extensions);
    fileRequestedMultiple.add(multiple);
    return files;
  }

  @override
  Future<String?> pickDirectory({String? confirmText}) async {
    directoryRequests++;
    return directory;
  }
}

class FakeWindowService implements WindowService {
  final List<String> calls = [];
  bool maximized = false;

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    calls.add('unmaximize');
    maximized = false;
  }

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> setPreventClose(bool prevent) async => calls.add('preventClose:$prevent');
}

class FakeDropTargetService implements DropTargetService {
  void Function(List<PickedFile> files)? _onDrop;
  void Function()? _onDragEntered;
  void Function()? _onDragExited;

  @override
  Widget dropTarget({
    required Widget child,
    required void Function(List<PickedFile> files) onDrop,
    void Function()? onDragEntered,
    void Function()? onDragExited,
  }) {
    _onDrop = onDrop;
    _onDragEntered = onDragEntered;
    _onDragExited = onDragExited;
    return child;
  }

  /// Simulates a drag entering the most recently built drop target.
  void enter() => _onDragEntered?.call();

  /// Simulates a drag leaving the most recently built drop target.
  void exit() => _onDragExited?.call();

  /// Simulates files dropped onto the most recently built drop target.
  void drop(List<PickedFile> files) => _onDrop?.call(files);
}

class FakeEmbeddedBrowserService implements EmbeddedBrowserService {
  FakeEmbeddedBrowserService({this.isNativeSupported = false});

  @override
  final bool isNativeSupported;
}

class FakeHttpService implements HttpService {
  final List<Uri> getRequests = [];
  final List<Uri> postRequests = [];
  http.Response Function(Uri uri) respond = (_) => http.Response('{}', 200);
  bool closed = false;

  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers, Duration? timeout}) async {
    getRequests.add(uri);
    return respond(uri);
  }

  @override
  Future<http.Response> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout}) async {
    postRequests.add(uri);
    return respond(uri);
  }

  @override
  void close() => closed = true;
}

class FakeFileSystemService implements FileSystemService {
  final Map<String, String> files = {};
  final Set<String> directories = {};

  /// Image paths the feature asked to show, in order.
  final List<String> imagesShown = [];

  @override
  String currentDirectory = '/fake/cwd';

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async => directories.contains(path);

  @override
  Future<String> readText(String path) async {
    final contents = files[path];
    if (contents == null) throw StateError('No fake file at $path');
    return contents;
  }

  @override
  Future<void> writeText(String path, String contents) async => files[path] = contents;

  @override
  Widget imageFile(
    String path, {
    double? width,
    double? height,
    BoxFit? fit,
    required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
  }) {
    imagesShown.add(path);
    return SizedBox(key: ValueKey('fake-image:$path'), width: width, height: height);
  }
}

class FakeProcessService implements ProcessService {
  final List<String> commands = [];
  ProcessOutput output = const ProcessOutput(exitCode: 0);

  /// Every process started with [start], in order. Tests push output into it and finish it.
  final List<FakeRunningProcess> started = [];

  @override
  Future<ProcessOutput> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async {
    commands.add([executable, ...arguments].join(' '));
    return output;
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async {
    commands.add([executable, ...arguments].join(' '));
    final process = FakeRunningProcess(startArguments: [executable, ...arguments], workingDirectory: workingDirectory);
    started.add(process);
    return process;
  }
}

/// A picked file for [path] with no bytes, for tests that only care about the path.
PickedFile fakePickedFile(String path) =>
    PickedFile(path: path, name: path.split('/').last, readBytes: () async => Uint8List(0));

/// A process the test controls: it emits stdout and stderr on demand and exits when told.
class FakeRunningProcess implements RunningProcess {
  FakeRunningProcess({required this.startArguments, this.workingDirectory});

  final List<String> startArguments;

  /// The working directory the process was started in, or null when none was given.
  final String? workingDirectory;

  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  /// Everything written to standard input, as text, in order.
  final List<String> written = [];

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void writeBytes(List<int> bytes) => written.add(utf8.decode(bytes));

  @override
  void writeLine(String line) => written.add('$line\n');

  @override
  bool kill() {
    if (_exit.isCompleted) return false;
    killed = true;
    return true;
  }

  void writeStdout(String text) => _stdout.add(utf8.encode(text));

  void writeStderr(String text) => _stderr.add(utf8.encode(text));

  /// Ends the process with [code] and closes its output streams.
  Future<void> exit(int code) async {
    if (!_exit.isCompleted) _exit.complete(code);
    await _stdout.close();
    await _stderr.close();
  }
}
