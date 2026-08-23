class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000/api/v1',
  );
  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );
  static const String defaultLanguage = 'rw';
  static const List<String> supportedLanguages = ['en', 'rw', 'fr', 'sw'];
}
