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
  FakeHostEnvironmentService({this.isWeb = false, Map<String, String> variables = const {}})
    : _variables = Map.of(variables);

  @override
  final bool isWeb;

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
  List<String> files = const [];
  String? directory;
  final List<List<String>> fileRequestedExtensions = [];
  int directoryRequests = 0;

  @override
  Future<List<String>> pickFiles({String? label, List<String> extensions = const []}) async {
    fileRequestedExtensions.add(extensions);
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
  void Function(List<String> paths)? _onDrop;

  @override
  Widget dropTarget({required Widget child, required void Function(List<String> paths) onDrop}) {
    _onDrop = onDrop;
    return child;
  }

  /// Simulates files dropped onto the most recently built drop target.
  void drop(List<String> paths) => _onDrop?.call(paths);
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
}

class FakeProcessService implements ProcessService {
  final List<String> commands = [];
  ProcessOutput output = const ProcessOutput(exitCode: 0);

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
}
