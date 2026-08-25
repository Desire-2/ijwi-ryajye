class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.22.202.231:8000/api/v1',
  );
  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'http://172.22.202.231:8000',
  );
  static const String defaultLanguage = 'rw';
  static const List<String> supportedLanguages = ['en', 'rw', 'fr', 'sw'];
}
