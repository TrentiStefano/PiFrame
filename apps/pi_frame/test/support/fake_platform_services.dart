import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pi_frame/data/platform/drop_target_service.dart';
import 'package:pi_frame/data/platform/embedded_browser_service.dart';
import 'package:pi_frame/data/platform/file_dialog_service.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/http_service.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:pi_frame/data/platform/process_service.dart';
import 'package:pi_frame/data/platform/user_data_service.dart';
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

  /// The web views the browser pane asked for, in order.
  final List<FakeEmbeddedWebView> webViews = [];

  @override
  EmbeddedWebView createWebView(EmbeddedWebViewEvents events) {
    final view = FakeEmbeddedWebView(events);
    webViews.add(view);
    return view;
  }
}

/// Records what the browser pane asks a web view to do. Tests call [events] to simulate navigation.
class FakeEmbeddedWebView implements EmbeddedWebView {
  FakeEmbeddedWebView(this.events);

  final EmbeddedWebViewEvents events;
  final List<Uri> loads = [];
  final List<bool> visibility = [];
  final List<String> calls = [];
  String? url;
  String? title;
  bool canBack = false;
  bool canForward = false;
  bool disposed = false;

  @override
  Widget get view => const SizedBox(key: ValueKey('fake-web-view'));

  @override
  Future<void> loadRequest(Uri uri) async => loads.add(uri);

  @override
  Future<void> setVisibility(bool visible) async => visibility.add(visible);

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<String?> getTitle() async => title;

  @override
  Future<bool> canGoBack() async => canBack;

  @override
  Future<void> goBack() async => calls.add('back');

  @override
  Future<bool> canGoForward() async => canForward;

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> openDevTools() async => calls.add('devTools');

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeHttpService implements HttpService {
  final List<Uri> getRequests = [];
  final List<Uri> postRequests = [];
  HttpResponse Function(Uri uri) respond = (uri) =>
      HttpResponse(statusCode: 200, bodyBytes: Uint8List.fromList(utf8.encode('{}')), url: uri);
  bool closed = false;

  @override
  Future<HttpResponse> get(Uri uri, {Map<String, String>? headers, Duration? timeout}) async {
    getRequests.add(uri);
    return respond(uri);
  }

  @override
  Future<HttpResponse> post(Uri uri, {Map<String, String>? headers, Object? body, Duration? timeout}) async {
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
  bool fileExistsSync(String path) => files.containsKey(path);

  @override
  bool directoryExistsSync(String path) => directories.contains(path);

  @override
  String? readTextSync(String path) => files[path];

  @override
  void writeTextSync(String path, String contents) => files[path] = contents;

  @override
  List<String> subdirectoryNamesSync(String path) => [
    for (final dir in directories)
      if (dir.startsWith('$path/') && !dir.substring(path.length + 1).contains('/')) dir.substring(path.length + 1),
  ];

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

/// The user's small data files (`~/.piframe/*.json`) held in memory. [writes] records every save, in order.
class FakeUserDataService implements UserDataService {
  final Map<String, String> files = {};
  final List<String> writes = [];

  @override
  String? read(String name) => files[name];

  @override
  void write(String name, String contents) {
    writes.add(name);
    files[name] = contents;
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
    String? workingDirectory,
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
