import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/platform/file_dialog_service.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:pi_frame/data/platform/process_service.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/attachment_model.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/attachment_chips.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_attachments_provider.dart';
import 'package:pi_frame/features/transcript/rich_content.dart';
import 'package:pi_frame/features/workspace/integrated_terminal.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:xterm/xterm.dart';

import 'support/fake_platform_services.dart';

// The transcript, composer and workspace features reach files, links, dialogs
// and processes only through the platform services. These tests swap in the
// fakes and assert what the feature asked each service to do.

const _session = 's_platform';

ThemeData _theme() => ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]);

ProviderContainer _container(List<Override> overrides) {
  return ProviderContainer(
    overrides: [
      sessionStateFamily(_session).overrideWith(
        (ref) =>
            SessionStateNotifier(_session, null)
              ..state = const SessionState(sessionId: _session, cwd: '/test', agentStatus: AgentStatus.settled),
      ),
      ...overrides,
    ],
  );
}

Widget _composerApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: _theme(),
      home: const Scaffold(
        body: SingleChildScrollView(child: Composer(sessionId: _session)),
      ),
    ),
  );
}

Future<void> _openAttachMenu(WidgetTester tester) async {
  // Tall enough that every attachment option is on screen to tap.
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.tap(find.byKey(const ValueKey('composer-attach-popup-btn')));
  await tester.pump();
  // Let the menu finish its opening animation before an option is tapped.
  await tester.pump(const Duration(milliseconds: 500));
}

PickedFile _picked(String path, String name) => PickedFile(path: path, name: name, readBytes: () async => Uint8List(0));

void main() {
  group('composer attachments come from the file dialog service', () {
    testWidgets('external file option attaches the files the picker returned', (tester) async {
      final dialog = FakeFileDialogService()..files = [_picked('/home/me/notes.txt', 'notes.txt')];
      final container = _container([fileDialogServiceProvider.overrideWithValue(dialog)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_composerApp(container));
      await tester.pump();
      await _openAttachMenu(tester);

      await tester.tap(find.byKey(const ValueKey('attach-option-external')));
      await tester.pump();
      await tester.pump();

      expect(dialog.fileRequestedExtensions, [<String>[]]);
      final attached = container.read(composerAttachmentsProvider(_session));
      expect(attached.map((a) => a.name), ['notes.txt']);
      expect(attached.single.type, AttachmentType.externalFile);
      expect(attached.single.pathOrUrl, '/home/me/notes.txt');
    });

    testWidgets('image option asks the picker for image types and attaches them as images', (tester) async {
      final dialog = FakeFileDialogService()..files = [_picked('/home/me/shot.png', 'shot.png')];
      final container = _container([fileDialogServiceProvider.overrideWithValue(dialog)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_composerApp(container));
      await tester.pump();
      await _openAttachMenu(tester);

      await tester.tap(find.byKey(const ValueKey('attach-option-image')));
      await tester.pump();
      await tester.pump();

      expect(dialog.fileRequestedExtensions.single, containsAll(['png', 'jpg', 'svg']));
      final attached = container.read(composerAttachmentsProvider(_session));
      expect(attached.single.type, AttachmentType.image);
      expect(attached.single.pathOrUrl, '/home/me/shot.png');
    });
  });

  group('attachment chips use the link and file system services', () {
    testWidgets('tapping a web link chip opens the link through the link service', (tester) async {
      final links = FakeLinkService();
      final container = _container([linkServiceProvider.overrideWithValue(links)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _theme(),
            home: const Scaffold(
              body: AttachmentChip(
                attachment: ChatAttachment(
                  id: 'link_1',
                  type: AttachmentType.webLink,
                  name: 'GitHub Repository',
                  pathOrUrl: 'https://github.com/test/repo',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('GitHub Repository'));
      await tester.pump();

      expect(links.opened, [Uri.parse('https://github.com/test/repo')]);
    });

    testWidgets('an image attachment is shown through the file system service', (tester) async {
      final files = FakeFileSystemService();
      final container = _container([fileSystemServiceProvider.overrideWithValue(files)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _theme(),
            home: const Scaffold(
              body: AttachmentChip(
                attachment: ChatAttachment(
                  id: 'img_1',
                  type: AttachmentType.image,
                  name: 'shot.png',
                  pathOrUrl: '/home/me/shot.png',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(files.imagesShown, contains('/home/me/shot.png'));
      expect(find.byKey(const ValueKey('fake-image:/home/me/shot.png')), findsWidgets);
    });
  });

  group('transcript links and file references use the link and process services', () {
    Widget richApp(ProviderContainer container, String text, {String? cwd}) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichContent(text: text, cwd: cwd),
            ),
          ),
        ),
      );
    }

    testWidgets('tapping a link in a message opens it through the link service', (tester) async {
      final links = FakeLinkService();
      final container = ProviderContainer(overrides: [linkServiceProvider.overrideWithValue(links)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(richApp(container, '[Flutter](https://flutter.dev)'));
      await tester.pump();

      await tester.tap(find.textContaining('Flutter', findRichText: true));
      await tester.pump();

      expect(links.opened, [Uri.parse('https://flutter.dev')]);
    });

    testWidgets('a file chip reveals the file folder through the process service on Linux', (tester) async {
      final processes = FakeProcessService();
      final files = FakeFileSystemService()..files['/home/me/repo/lib/main.dart'] = '';
      final host = FakeHostEnvironmentService(operatingSystem: 'linux');
      final container = ProviderContainer(
        overrides: [
          processServiceProvider.overrideWithValue(processes),
          fileSystemServiceProvider.overrideWithValue(files),
          hostEnvironmentServiceProvider.overrideWithValue(host),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(richApp(container, 'Ho modificato il file `lib/main.dart`.', cwd: '/home/me/repo'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.insert_drive_file_outlined).first);
      await tester.pump();
      await tester.pump();

      expect(processes.commands, ['xdg-open /home/me/repo/lib']);
    });
  });

  group('integrated terminal runs its shell through the process service', () {
    testWidgets('opens the shell in the workspace folder', (tester) async {
      final processes = FakeProcessService();
      final files = FakeFileSystemService()..directories.add('/work/proj');
      final host = FakeHostEnvironmentService(operatingSystem: 'linux', variables: {'SHELL': '/bin/zsh'});
      final container = ProviderContainer(
        overrides: [
          processServiceProvider.overrideWithValue(processes),
          fileSystemServiceProvider.overrideWithValue(files),
          hostEnvironmentServiceProvider.overrideWithValue(host),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _theme(),
            home: Scaffold(
              body: IntegratedTerminalPanel(
                cwd: '/work/proj',
                tokens: FrameTokens.dark,
                onCollapseDownward: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(processes.started.map((p) => p.startArguments.join(' ')), ['/bin/zsh -i']);
      expect(processes.started.map((p) => p.workingDirectory), ['/work/proj']);
    });

    testWidgets('closing the panel stops the shell process', (tester) async {
      final processes = FakeProcessService();
      final host = FakeHostEnvironmentService(operatingSystem: 'linux', variables: {'SHELL': '/bin/zsh'});
      final container = ProviderContainer(
        overrides: [
          processServiceProvider.overrideWithValue(processes),
          fileSystemServiceProvider.overrideWithValue(FakeFileSystemService()),
          hostEnvironmentServiceProvider.overrideWithValue(host),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _theme(),
            home: Scaffold(
              body: IntegratedTerminalPanel(
                cwd: '',
                tokens: FrameTokens.dark,
                onCollapseDownward: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(processes.started.single.killed, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(processes.started.single.killed, isTrue);
    });

    test('a submitted command line is written to the shell and Ctrl+C reaches it', () {
      final process = FakeRunningProcess(startArguments: const []);
      final session = TerminalTabSession(id: 'term_1', title: 'zsh 1', shellName: 'zsh', terminal: Terminal())
        ..process = process;

      session.handleInput('ls');
      session.handleInput('\r');
      session.handleInput('\x03');

      expect(process.written, ['ls\n', '\u0003']);
      session.dispose();
    });
  });
}
