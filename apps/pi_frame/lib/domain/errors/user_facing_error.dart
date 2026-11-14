import 'dart:async';
import 'dart:io';

import '../../data/daemon/attachment_upload.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_errors.dart';
import '../../data/language/strings_workspace.dart';
import '../../data/update/github_update_client.dart';

/// A failure translated into something a person can act on.
///
/// [title] and [hint] are safe to show. When [isProtocolMessage] is true the
/// [title] is the message the daemon, Pi or the update client wrote for the
/// user, shown as is. [details] is the raw text, meant only for a collapsed
/// "Dettagli" section.
class UserFacingError {
  final String title;
  final String? hint;
  final String details;
  final bool retryable;

  /// True when [title] is a human-readable message from the daemon, Pi or the
  /// update client, rather than localized copy from this app.
  final bool isProtocolMessage;

  /// True when the error is a raw Dart failure that matched no known case.
  /// [title] is the generic copy and the raw text is only in [details].
  final bool isGeneric;

  const UserFacingError({
    required this.title,
    this.hint,
    required this.details,
    this.retryable = false,
    this.isProtocolMessage = false,
    this.isGeneric = false,
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

/// Text that is a Dart internal dump rather than a message for a person.
final _internalShape = RegExp(
  r"Instance of '|type '.+' is not a subtype|Null check operator|package:|dart:|\n|^#\d+\s",
);

/// The human-readable message carried by a protocol error, or null when [error]
/// is a raw Dart exception (or text that looks like one).
///
/// Protocol errors are [PcpException] (daemon and Pi replies), [UpdateException]
/// and [AttachmentUploadException]. A plain [String] is treated as a message
/// the caller already extracted from such an error.
String? _protocolMessage(Object error) {
  final String raw;
  if (error is PcpException) {
    raw = error.message.toString();
  } else if (error is UpdateException) {
    raw = error.message;
  } else if (error is AttachmentUploadException) {
    raw = error.message;
  } else if (error is String) {
    raw = error;
  } else {
    return null;
  }
  final text = raw.replaceFirst(_rawPrefix, '').trim();
  if (text.isEmpty || _internalShape.hasMatch(text)) return null;
  return text;
}

/// Maps a raw error (an exception, or its text) to a [UserFacingError].
///
/// Known failures (daemon unreachable, Git missing, timeouts and so on) map to
/// localized copy first. Otherwise a protocol message is shown as is. A raw
/// Dart exception with no known cause becomes a generic failure with the raw
/// text kept in `details`.
UserFacingError describeError(Object error, AppStrings s) {
  if (error is UserMessageException) {
    return UserFacingError(
      title: error.message,
      details: error.message,
      isProtocolMessage: true,
    );
  }
  final protocol = _protocolMessage(error);
  final details = protocol ?? error.toString().replaceFirst(_rawPrefix, '');
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
  if (protocol != null) {
    return UserFacingError(
      title: protocol,
      details: protocol,
      retryable: true,
      isProtocolMessage: true,
    );
  }
  return UserFacingError(
    title: s.errorUnknownTitle,
    details: details,
    retryable: true,
    isGeneric: true,
  );
}

/// Snackbar text for a failed action.
///
/// - Known failure: "[prefix]: [title]. [hint]".
/// - Protocol message: "[prefix]: [message]", the message exactly as sent.
/// - Raw Dart exception: "[prefix].", so no raw text is shown.
String failureText(AppStrings s, String prefix, Object error) {
  final e = describeError(error, s);
  if (e.isGeneric) return '$prefix.';
  if (e.hint == null && e.isProtocolMessage) return '$prefix: ${e.title}';
  return '$prefix: ${e.summary}${e.hint == null ? '.' : ''}';
}
