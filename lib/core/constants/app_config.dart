class AppConfig {
  static const int currentVersionCode = 60;
  static const String currentVersionName = '1.0.0+60';
  static const String appName = 'Stagiaire';
}

/// Google Sign-In (Android). The WEB client ID is used as `serverClientId` so
/// Google issues an ID token that Supabase can verify. Not a secret.
/// Google Cloud project: "stagiaire" (gen-lang-client-0249395631).
class GoogleAuthConfig {
  static const String webClientId =
      '183919287524-9fasfnf3g0ga9rpcg2leni2t987ved5h.apps.googleusercontent.com';
}
