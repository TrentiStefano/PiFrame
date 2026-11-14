import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_errors.dart';
import 'package:pi_frame/data/language/strings_composer.dart';
import 'package:pi_frame/data/language/strings_workspace.dart';
import 'package:pi_frame/data/update/github_update_client.dart';
import 'package:pi_frame/domain/errors/user_facing_error.dart';

void main() {
  const it = AppStrings(AppLanguage.it);
  const en = AppStrings(AppLanguage.en);

  group('describeError mapping (Italian)', () {
    test('an outdated daemon maps to the rebuild hint', () {
      final e = describeError(
        StateError('Unsupported command type: workspace.listFiles'),
        it,
      );
      expect(e.title, it.errorOutdatedDaemonTitle);
      expect(e.hint, it.repositoryDaemonOutdatedError);
      expect(e.retryable, isFalse);
    });

    test('a non-repository folder maps to the repository title', () {
      final e = describeError(
        PcpException(
          'Session working directory is not inside a Git repository.',
          code: 'WORKSPACE_NOT_REPOSITORY',
        ),
        it,
      );
      expect(e.title, it.errorNotRepositoryTitle);
      expect(e.hint, it.errorNotRepositoryHint);
      expect(e.retryable, isFalse);
    });

    test('a missing git executable maps to the install hint', () {
      final e = describeError(
        Exception('spawn git ENOENT'),
        it,
      );
      expect(e.title, it.errorGitMissingTitle);
      expect(e.retryable, isFalse);
    });

    test('a missing session maps to the session title', () {
      final e = describeError(StateError('Session abc not found'), it);
      expect(e.title, it.errorSessionMissingTitle);
    });

    test('a disconnected daemon maps to the reachability hint', () {
      final e = describeError(StateError('Daemon non connesso'), it);
      expect(e.title, it.errorDaemonUnreachableTitle);
      expect(e.hint, it.errorDaemonUnreachableHint);
      expect(e.retryable, isTrue);
    });

    test('a refused connection is treated as an unreachable daemon', () {
      final e = describeError(
        const SocketException('Connection refused', osError: OSError()),
        it,
      );
      expect(e.title, it.errorDaemonUnreachableTitle);
      expect(e.retryable, isTrue);
    });

    test('a timeout maps to the timeout title and is retryable', () {
      final e = describeError(
        TimeoutException('Future not completed', const Duration(seconds: 10)),
        it,
      );
      expect(e.title, it.errorTimeoutTitle);
      expect(e.hint, it.errorTimeoutHint);
      expect(e.retryable, isTrue);
    });

    test('a read-only or busy daemon maps to the busy title', () {
      final e = describeError(
        PcpException(
          'Workspace is read-only while Pi is working',
          code: 'COMMAND_REJECTED',
        ),
        it,
      );
      expect(e.title, it.errorBusyTitle);
      expect(e.retryable, isTrue);
    });

    test('a permission error maps to the permission title', () {
      final e = describeError(
        const FileSystemException(
          'Cannot open file',
          '/x',
          OSError('Permission denied', 13),
        ),
        it,
      );
      expect(e.title, it.errorPermissionTitle);
      expect(e.retryable, isFalse);
    });

    test('a missing file maps to the not-found title', () {
      final e = describeError(
        const FileSystemException(
          'Cannot open file',
          '/x',
          OSError('No such file or directory', 2),
        ),
        it,
      );
      expect(e.title, it.errorNotFoundTitle);
    });

    test('a network failure maps to the network title and is retryable', () {
      final e = describeError(
        const SocketException('Failed host lookup: api.github.com'),
        it,
      );
      expect(e.title, it.errorNetworkTitle);
      expect(e.retryable, isTrue);
    });

    test('an unknown error keeps the raw text in details only', () {
      final e = describeError(StateError('boom-42'), it);
      expect(e.title, 'Operazione non riuscita');
      expect(e.hint, isNull);
      expect(e.details, 'boom-42');
      expect(e.summary, 'Operazione non riuscita');
    });

    test('details drop the Dart exception prefix', () {
      expect(describeError(StateError('x'), it).details, 'x');
      expect(describeError(Exception('y'), it).details, 'y');
    });

    test('app-authored copy is shown as is', () {
      final e = describeError(
        const UserMessageException('Il daemon non ha verificato la versione.'),
        it,
      );
      expect(e.title, 'Il daemon non ha verificato la versione.');
      expect(e.hint, isNull);
    });

    test('a raw string is described the same way as an exception', () {
      final e = describeError('Session working directory is not inside a Git repository.', it);
      expect(e.title, it.errorNotRepositoryTitle);
    });
  });

  group('protocol messages are shown, raw Dart exceptions are not', () {
    test('a daemon reply (PcpException) shows its message as the title', () {
      final e = describeError(
        PcpException('installed version 0.1.15, expected 1.2.0',
            code: 'PACKAGE_UPDATE_FAILED'),
        it,
      );
      expect(e.title, 'installed version 0.1.15, expected 1.2.0');
      expect(e.isProtocolMessage, isTrue);
      expect(e.isGeneric, isFalse);
      expect(e.details, e.title);
    });

    test('an update client message (UpdateException) is shown as is', () {
      final e = describeError(
        const UpdateException('Download annullato dall\'utente.'),
        it,
      );
      expect(e.title, 'Download annullato dall\'utente.');
      expect(e.isProtocolMessage, isTrue);
    });

    test('a provider message in a string is shown after the Dart prefix', () {
      final e = describeError('Exception: Model unavailable', it);
      expect(e.title, 'Model unavailable');
      expect(e.isProtocolMessage, isTrue);
    });

    test('failureText keeps a provider message visible', () {
      expect(
        failureText(it, 'Invio non riuscito', 'Model unavailable'),
        'Invio non riuscito: Model unavailable',
      );
      expect(
        failureText(
          it,
          'Invio non riuscito',
          PcpException('Model unavailable', code: 'PROVIDER_ERROR'),
        ),
        'Invio non riuscito: Model unavailable',
      );
    });

    test('an upload failure keeps the daemon reason and hides raw text', () {
      expect(
        it.composerUploadFailed(
          'a.png',
          PcpException('Quota exceeded', code: 'UPLOAD_REJECTED'),
        ),
        'Caricamento di "a.png" non riuscito: Quota exceeded',
      );
      expect(
        it.composerUploadFailed('a.png', StateError('boom-9')),
        'Caricamento di "a.png" non riuscito.',
      );
    });

    test('a raw Dart exception is still mapped, never shown', () {
      final e = describeError(StateError('Package download failed'), it);
      expect(e.isGeneric, isTrue);
      expect(e.title, 'Operazione non riuscita');
      expect(e.details, 'Package download failed');
    });

    test('a string that looks like a Dart dump is treated as raw', () {
      final e = describeError("Instance of 'Foo'", it);
      expect(e.isGeneric, isTrue);
      expect(e.title, 'Operazione non riuscita');
    });

    test('a known protocol failure still maps to its localized title', () {
      final e = describeError(
        PcpException('Workspace is read-only while Pi is working',
            code: 'COMMAND_REJECTED'),
        it,
      );
      expect(e.title, it.errorBusyTitle);
      expect(e.isProtocolMessage, isFalse);
    });
  });

  group('describeError mapping (English)', () {
    test('an unknown error uses the English generic title', () {
      final e = describeError(StateError('boom'), en);
      expect(e.title, 'Operation failed');
      expect(e.hint, isNull);
    });

    test('a disconnected daemon uses English copy', () {
      final e = describeError(StateError('Daemon not connected'), en);
      expect(e.title, 'Daemon unreachable');
    });
  });

  group('failureText', () {
    test('a known error appends the title and hint to the prefix', () {
      final text = failureText(
        it,
        'Invio non riuscito',
        StateError('Daemon non connesso'),
      );
      expect(
        text,
        'Invio non riuscito: Daemon non raggiungibile. '
        'Verifica che il daemon PiFrame sia in esecuzione, poi riprova.',
      );
    });

    test('an unknown error shows only the prefix, never the raw text', () {
      expect(
        failureText(it, 'Invio non riuscito', StateError('Model unavailable')),
        'Invio non riuscito.',
      );
    });
  });
}
