import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/providers/app_provider.dart';
import 'core/services/supabase_service.dart';
import 'core/services/cache_service.dart';
import 'core/theme/app_theme.dart';
import 'core/services/app_update_service.dart';
import 'core/services/pdf_storage_service.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set larger image cache limits to keep loaded slide images in RAM/VRAM
  // and prevent reloading/flickering when navigating between screens.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 300 * 1024 * 1024; // 300 MB
  PaintingBinding.instance.imageCache.maximumSize = 150; // 150 images

  // Initialize Core Services
  try {
    await SupabaseService.initialize();
    await CacheService().initialize();
    await AppUpdateService().initialize();
    await PdfStorageService.migrateOldPdfFiles();
  } catch (e) {
    print('Failed to initialize Stagiaire core services: $e');
  }

  runApp(const StagiaireApp());
}

class StagiaireApp extends StatelessWidget {
  const StagiaireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppProvider()..initializeData(),
        ),
      ],
      child: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return MaterialApp(
            title: 'Stagiaire Quiz Bank',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: provider.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
            locale: const Locale('ar', 'AE'), // RTL Localization default
            supportedLocales: const [
              Locale('ar', 'AE'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
