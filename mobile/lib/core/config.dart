class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ijwi-ryajye-1.onrender.com/api/v1',
  );
  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'https://ijwi-ryajye-1.onrender.com',
  );
  static const String defaultLanguage = 'rw';
  static const List<String> supportedLanguages = ['en', 'rw', 'fr', 'sw'];
}
