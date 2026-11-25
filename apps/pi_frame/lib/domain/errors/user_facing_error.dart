/// A failure translated into something a person can act on.
///
/// [title] and [hint] are safe to show. When [isProtocolMessage] is true the
/// [title] is the message the daemon, Pi or the update client wrote for the
/// user, shown as is. [details] is the raw text, meant only for a collapsed
/// "Dettagli" section.
///
/// The mapping from raw errors to this model lives in data/errors/
/// (user_facing_error_mapping.dart).
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
/// so the error mapping shows it as is instead of a generic failure.
class UserMessageException implements Exception {
  final String message;
  const UserMessageException(this.message);

  @override
  String toString() => message;
}
