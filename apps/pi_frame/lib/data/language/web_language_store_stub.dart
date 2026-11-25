/// Non-web builds keep the language in ~/.piframe/language_settings.json.
String? readWebLanguage() => null;

void writeWebLanguage(String code) {}

/// Non-web builds have no browser language.
String? readBrowserLanguage() => null;
