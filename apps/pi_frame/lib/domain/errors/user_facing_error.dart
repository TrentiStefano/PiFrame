import 'dart:async';
import 'dart:io';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_errors.dart';
import '../../data/language/strings_workspace.dart';

/// A raw failure translated into something a person can act on.
///
/// [title] and [hint] are localized and safe to show. [details] is the raw
/// text, meant only for a collapsed "Dettagli" section.
class UserFacingError {
  final String title;
  final String? hint;
  final String details;
  final bool retryable;

  const UserFacingError({
    required this.title,
    this.hint,
    required this.details,
    this.retryable = false,
  });

  /// Title and hint on one line, for snackbars and compact labels.
  String get summary => hint == null ? title : '$title. $hint';
}

/// An exception whose message is already localized copy written by the app,
/// so [describeError] shows it as is instead of a generic failure.
class UserMessageException implements Exception {
  final String message;
  const UserMessageException(this.message);

  @override
  String toString() => message;
}

final _rawPrefix = RegExp(r'^(Bad state|Exception|StateError|FormatException):\s*');

/// Maps a raw error (an exception, or its text) to a [UserFacingError].
///
/// Matching is by exception type where one exists, and otherwise by the
/// message text the daemon and Git layers produce. Anything unrecognized is
/// reported as a generic failure with the raw text kept in `details`.
UserFacingError describeError(Object error, AppStrings s) {
  if (error is UserMessageException) {
    return UserFacingError(
      title: error.message,
      details: error.message,
    );
  }
  final details = error.toString().replaceFirst(_rawPrefix, '');
  final lower = error.toString().toLowerCase();

  UserFacingError known(String title, String? hint, {bool retryable = false}) =>
      UserFacingError(
        title: title,
        hint: hint,
        details: details,
        retryable: retryable,
      );

  bool has(List<String> needles) => needles.any(lower.contains);

  if (has(['unsupported command type'])) {
    return known(s.errorOutdatedDaemonTitle, s.repositoryDaemonOutdatedError);
  }
  if (has([
    'not inside a git repository',
    'not a git repository',
    'workspace_not_repository',
  ])) {
    return known(s.errorNotRepositoryTitle, s.errorNotRepositoryHint);
  }
  if (has([
    'spawn git',
    'git enoent',
    'git: command not found',
    'git was not found',
  ])) {
    return known(s.errorGitMissingTitle, s.errorGitMissingHint);
  }
  if (RegExp(r'session( \S+)? not found').hasMatch(lower) ||
      has(['session_not_found'])) {
    return known(s.errorSessionMissingTitle, s.errorSessionMissingHint);
  }
  if (has([
    'daemon non connesso',
    'daemon disconnected',
    'daemon not connected',
    'pcp websocket',
    'websocketexception',
    'websocketchannelexception',
    'connection refused',
  ])) {
    return known(s.errorDaemonUnreachableTitle, s.errorDaemonUnreachableHint,
        retryable: true);
  }
  if (has(['command_rejected', 'read-only', 'agent is working', 'pi is working'])) {
    return known(s.errorBusyTitle, s.errorBusyHint, retryable: true);
  }
  if (error is TimeoutException || has(['timed out', 'timeoutexception'])) {
    return known(s.errorTimeoutTitle, s.errorTimeoutHint, retryable: true);
  }
  if (has([
    'permission denied',
    'access is denied',
    'eacces',
    'eperm',
    'operation not permitted',
  ])) {
    return known(s.errorPermissionTitle, s.errorPermissionHint);
  }
  if (has([
    'no such file',
    'enoent',
    'does not exist',
    'file_not_found',
  ])) {
    return known(s.errorNotFoundTitle, s.errorNotFoundHint);
  }
  if (error is SocketException ||
      error is HttpException ||
      has([
        'failed host lookup',
        'network is unreachable',
        'no route to host',
        'handshakeexception',
      ])) {
    return known(s.errorNetworkTitle, s.errorNetworkHint, retryable: true);
  }
  // Unknown failures are retryable; call sites show Riprova only when they can retry.
  return known(s.errorUnknownTitle, null, retryable: true);
}

/// Snackbar text for a failed action: "[prefix]: [title]. [hint]", or just
/// "[prefix]." when the error is not recognized, so no raw text is shown.
String failureText(AppStrings s, String prefix, Object error) {
  final e = describeError(error, s);
  if (e.title == s.errorUnknownTitle) return '$prefix.';
  return '$prefix: ${e.summary}${e.hint == null ? '.' : ''}';
}
