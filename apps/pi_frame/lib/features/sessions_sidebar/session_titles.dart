import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/session_state.dart';

/// Longest provisional title taken from the first prompt, in characters.
const int provisionalTitleMaxLength = 60;

/// Names the daemon gives a session that was never renamed: an empty name, the
/// session id, or the `Session HH:MM[:SS]` default created at start.
final RegExp _daemonDefaultName = RegExp(
  r'^Session \d{1,2}:\d{2}(:\d{2})?( ?[AaPp][Mm])?$',
);

/// Whether [name] is a title the user or Pi chose, as opposed to a placeholder.
/// A user rename or a title from Pi always wins over the provisional title.
bool hasChosenSessionName(String? name, String id) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == id) return false;
  return !_daemonDefaultName.hasMatch(trimmed);
}

/// Text of the first user message in a loaded session, or null when the
/// session has no loaded user prompt yet.
String? firstUserPrompt(SessionState state) {
  for (final entry in state.entries) {
    if (entry.role != 'user') continue;
    final text = entry.text.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// Collapses whitespace and cuts [text] to [maxLength] characters with an
/// ellipsis. Text that already fits is returned unchanged.
String truncateProvisionalTitle(
  String text, {
  int maxLength = provisionalTitleMaxLength,
}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxLength) return flat;
  return '${flat.substring(0, maxLength - 1).trimRight()}…';
}

/// The title the sessions rail shows for one session.
///
/// Order: a chosen name (rename or Pi title) first, then the first user prompt
/// truncated to about 60 characters, then the untitled label when there is no
/// prompt yet. [prompt] is the first prompt from the loaded session state.
/// [listedPrompt] is the first prompt the daemon lists for sessions that are
/// not loaded; it is used when [prompt] is missing. [lastPreview] is the last
/// message and is the final stopgap for sessions with no prompt at all.
String sessionRailTitle({
  required String id,
  required String? name,
  required String? qualifiedName,
  required String? prompt,
  required int? messageCount,
  required String? lastPreview,
  required AppStrings strings,
  String? listedPrompt,
}) {
  if (hasChosenSessionName(name, id)) {
    // Qualified by repository when another session has the same name.
    final qualified = qualifiedName?.trim() ?? '';
    return qualified.isNotEmpty ? qualified : name!.trim();
  }
  final first = prompt?.trim() ?? '';
  if (first.isNotEmpty) return truncateProvisionalTitle(first);
  final listed = listedPrompt?.trim() ?? '';
  if (listed.isNotEmpty) return truncateProvisionalTitle(listed);
  if (messageCount == 0) return strings.sessionUntitledTitle;
  final preview = lastPreview?.trim() ?? '';
  if (preview.isNotEmpty) return truncateProvisionalTitle(preview);
  return strings.sessionUntitledTitle;
}

/// "2 h fa" style label for a last-activity time in epoch milliseconds, or null
/// when the time is unknown.
String? relativeTimeLabel(AppStrings strings, int? epochMs, {int? nowMs}) {
  if (epochMs == null || epochMs <= 0) return null;
  final diff = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - epochMs;
  if (diff < 60000) return strings.relativeJustNow;
  final minutes = diff ~/ 60000;
  if (minutes < 60) return strings.relativeMinutesAgo(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) return strings.relativeHoursAgo(hours);
  return strings.relativeDaysAgo(hours ~/ 24);
}
