import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../domain/session/context_pricing_helper.dart';

/// The size with its pricing tier, in the language of [strings].
String formatContextSize(int size, int fullWindow, AppStrings strings) =>
    strings.contextSizeWithTier(formatTokens(size), extended: size >= fullWindow);
