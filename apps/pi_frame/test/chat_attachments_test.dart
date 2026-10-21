import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/attachment_model.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_attachments_provider.dart';
import 'package:pi_frame/features/transcript/chat_drop_target.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  group('Attachment model tests', () {
    test('encodeAttachmentsTag and parseAttachmentsFromText round-trip correctly', () {
      final attachments = [
        const ChatAttachment(
          id: 'att_1',
          type: AttachmentType.repoFile,
          name: 'main.dart',
          pathOrUrl: 'lib/main.dart',
        ),
        const ChatAttachment(
          id: 'att_2',
          type: AttachmentType.externalFile,
          name: 'notes.txt',
          pathOrUrl: '/Users/test/notes.txt',
        ),
        const ChatAttachment(
          id: 'att_3',
          type: AttachmentType.webLink,
          name: 'Flutter Docs',
          pathOrUrl: 'https://flutter.dev',
        ),
        const ChatAttachment(
          id: 'att_4',
          type: AttachmentType.image,
          name: 'screenshot.png',
          pathOrUrl: '/Users/test/screenshot.png',
        ),
      ];

      final tag = encodeAttachmentsTag(attachments);
      final rawMessage = '$tag\nHere is my question about the code.';

      final (cleanText, parsed) = parseAttachmentsFromText(rawMessage);

      expect(cleanText, 'Here is my question about the code.');
      expect(parsed.length, 4);
      expect(parsed[0].type, AttachmentType.repoFile);
      expect(parsed[0].name, 'main.dart');
      expect(parsed[1].type, AttachmentType.externalFile);
      expect(parsed[1].name, 'notes.txt');
      expect(parsed[2].type, AttachmentType.webLink);
      expect(parsed[2].pathOrUrl, 'https://flutter.dev');
      expect(parsed[3].type, AttachmentType.image);
      expect(parsed[3].name, 'screenshot.png');
    });

    test('isImageExtension detects standard image formats', () {
      expect(isImageExtension('photo.PNG'), isTrue);
      expect(isImageExtension('banner.jpg'), isTrue);
      expect(isImageExtension('preview.jpeg'), isTrue);
      expect(isImageExtension('anim.gif'), isTrue);
      expect(isImageExtension('thumb.webp'), isTrue);
      expect(isImageExtension('icon.svg'), isTrue);
      expect(isImageExtension('main.dart'), isFalse);
      expect(isImageExtension('README.md'), isFalse);
    });
  });

  group('Composer attach popup-dropdown and chips tests', () {
    Widget wrapComposer(WidgetRef? Function(WidgetRef)? onRef) {
      return ProviderScope(
        overrides: [
          sessionStateFamily('s_att_test').overrideWith(
            (ref) => SessionStateNotifier('s_att_test', null)
              ..state = const SessionState(
                sessionId: 's_att_test',
                cwd: '/test',
                agentStatus: AgentStatus.settled,
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Composer(sessionId: 's_att_test'),
            ),
          ),
        ),
      );
    }

    testWidgets('shows popup-dropdown with 4 attachment options on attach button click', (
      tester,
    ) async {
      await tester.pumpWidget(wrapComposer(null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Locate attach popup button
      final attachBtn = find.byKey(const ValueKey('composer-attach-popup-btn'));
      expect(attachBtn, findsOneWidget);

      await tester.tap(attachBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify the 4 options appear in the popup-dropdown
      expect(find.byKey(const ValueKey('attach-option-repo')), findsOneWidget);
      expect(find.text('File dal repository'), findsOneWidget);

      expect(find.byKey(const ValueKey('attach-option-external')), findsOneWidget);
      expect(find.text('File esterno'), findsOneWidget);

      expect(find.byKey(const ValueKey('attach-option-link')), findsOneWidget);
      expect(find.text('Link web'), findsOneWidget);

      expect(find.byKey(const ValueKey('attach-option-image')), findsOneWidget);
      expect(find.text('Immagine'), findsOneWidget);
    });

    testWidgets('renders attachment chips in composer and allows removing', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('s_att_test').overrideWith(
            (ref) => SessionStateNotifier('s_att_test', null)
              ..state = const SessionState(
                sessionId: 's_att_test',
                cwd: '/test',
                agentStatus: AgentStatus.settled,
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Add pre-existing attachments to composer
      container.read(composerAttachmentsProvider('s_att_test').notifier).addAll([
        const ChatAttachment(
          id: 'test_file_1',
          type: AttachmentType.repoFile,
          name: 'pubspec.yaml',
          pathOrUrl: 'pubspec.yaml',
        ),
        const ChatAttachment(
          id: 'test_link_1',
          type: AttachmentType.webLink,
          name: 'GitHub Repository',
          pathOrUrl: 'https://github.com/test/repo',
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Composer(sessionId: 's_att_test'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify attachments row
      expect(find.byKey(const ValueKey('composer-attachments-bar')), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
      expect(find.text('GitHub Repository'), findsOneWidget);

      // Remove pubspec.yaml
      final removeBtn = find.byKey(const ValueKey('attachment-remove-test_file_1'));
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // pubspec.yaml is removed, link remains
      expect(find.text('pubspec.yaml'), findsNothing);
      expect(find.text('GitHub Repository'), findsOneWidget);
    });
  });

  group('Chat transcript attachments rendering and lightbox tests', () {
    testWidgets('renders file box, web link, and image preview with lightbox popup', (
      tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync('pi_frame_img_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      // Create a dummy image file
      final testImg = File('${tempDir.path}/test_preview.png');
      testImg.writeAsBytesSync([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      final attachments = [
        const ChatAttachment(
          id: 'user_att_file',
          type: AttachmentType.repoFile,
          name: 'database.sql',
          pathOrUrl: 'sql/database.sql',
        ),
        const ChatAttachment(
          id: 'user_att_link',
          type: AttachmentType.webLink,
          name: 'Dashboard URL',
          pathOrUrl: 'https://dashboard.example.com',
        ),
        ChatAttachment(
          id: 'user_att_img',
          type: AttachmentType.image,
          name: 'diagram.png',
          pathOrUrl: testImg.path,
        ),
      ];

      final tag = encodeAttachmentsTag(attachments);
      final rawUserText = '$tag\nPlease review these assets.';

      final entry = SessionEntry(
        id: 'msg_user_1',
        role: 'user',
        text: rawUserText,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final state = SessionState(
        sessionId: 's_view_test',
        cwd: '/test',
        entries: [entry],
        agentStatus: AgentStatus.settled,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_view_test').overrideWith(
              (ref) => SessionStateNotifier('s_view_test', null)..state = state,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TranscriptView(sessionId: 's_view_test'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. File box is present with icon and filename
      final fileChipFinder = find.byKey(const ValueKey('attachment-file-user_att_file'));
      expect(fileChipFinder, findsOneWidget);
      expect(find.descendant(of: fileChipFinder, matching: find.byIcon(Icons.folder_outlined)), findsOneWidget);
      expect(find.descendant(of: fileChipFinder, matching: find.text('database.sql')), findsOneWidget);

      // 2. Clickable Web link is present with link icon
      final linkChipFinder = find.byKey(const ValueKey('attachment-link-user_att_link'));
      expect(linkChipFinder, findsOneWidget);
      expect(find.descendant(of: linkChipFinder, matching: find.byIcon(Icons.link)), findsOneWidget);
      expect(find.descendant(of: linkChipFinder, matching: find.text('Dashboard URL')), findsOneWidget);

      // 3. User message text is clean
      expect(find.text('Please review these assets.'), findsOneWidget);

      // 4. Tiny preview image is present
      final imageThumbFinder = find.byKey(const ValueKey('attachment-image-user_att_img'));
      expect(imageThumbFinder, findsOneWidget);

      // Tap the image thumbnail -> opens big lightbox popup
      await tester.tap(imageThumbFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('image-lightbox-dialog')), findsOneWidget);
      expect(find.text('diagram.png'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Close the lightbox dialog
      await tester.tap(find.byTooltip('Chiudi anteprima'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('image-lightbox-dialog')), findsNothing);
    });
  });

  group('ChatDropTarget drag and drop tests', () {
    testWidgets('shows animated hover overlay on drag and attaches files on drop', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: ChatDropTarget(
                sessionId: 's_drop_test',
                child: SizedBox(
                  width: 400,
                  height: 400,
                  child: Text('Chat Content'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Chat Content'), findsOneWidget);
      // Overlay initially has opacity 0.0
      final opacityFinder = find.byKey(const ValueKey('chat-drop-overlay-opacity'));
      expect(opacityFinder, findsOneWidget);
      final AnimatedOpacity initialOpacityWidget = tester.widget(opacityFinder);
      expect(initialOpacityWidget.opacity, 0.0);

      // Simulate onDragEntered on DropTarget
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragEntered?.call(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Overlay is visible
      final AnimatedOpacity activeOpacityWidget = tester.widget(opacityFinder);
      expect(activeOpacityWidget.opacity, 1.0);
      expect(find.text('Rilascia i file qui per allegarli'), findsOneWidget);

      // Simulate onDragDone with a dropped file and an image
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
          files: [
            DropItemFile('/path/to/script.py', name: 'script.py'),
            DropItemFile('/path/to/diagram.png', name: 'diagram.png'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Overlay fades back to 0.0
      final AnimatedOpacity postOpacityWidget = tester.widget(opacityFinder);
      expect(postOpacityWidget.opacity, 0.0);

      // Files are attached to composerAttachmentsProvider('s_drop_test')
      final attachments = container.read(composerAttachmentsProvider('s_drop_test'));
      expect(attachments.length, 2);
      expect(attachments[0].name, 'script.py');
      expect(attachments[0].type, AttachmentType.externalFile);
      expect(attachments[1].name, 'diagram.png');
      expect(attachments[1].type, AttachmentType.image);
    });

    testWidgets('renders assistant attachments and base64 data URIs without leaking raw attachment tags', (tester) async {
      // 1x1 transparent GIF base64 data URI
      const dataUri = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
      final asstAttachments = [
        const ChatAttachment(
          id: 'asst_att_img',
          type: AttachmentType.image,
          name: 'generated_chart.gif',
          pathOrUrl: dataUri,
        ),
      ];

      final tag = encodeAttachmentsTag(asstAttachments);
      final rawAsstText = 'Here is the chart you requested.\n$tag';

      final entry = SessionEntry(
        id: 'msg_asst_1',
        role: 'assistant',
        text: rawAsstText,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final state = SessionState(
        sessionId: 's_asst_att_test',
        cwd: '/test',
        entries: [entry],
        agentStatus: AgentStatus.settled,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_asst_att_test').overrideWith(
              (ref) => SessionStateNotifier('s_asst_att_test', null)..state = state,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TranscriptView(sessionId: 's_asst_att_test'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Image thumbnail is rendered for the assistant attachment
      final imgChipFinder = find.byKey(const ValueKey('attachment-image-asst_att_img'));
      expect(imgChipFinder, findsOneWidget);

      // 2. Clean message text is visible
      expect(find.textContaining('Here is the chart you requested.'), findsOneWidget);

      // 3. Raw attachment comment tag is NOT leaked to user
      expect(find.textContaining('<!--pi-attachments:'), findsNothing);
    });
  });
}
