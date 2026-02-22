import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/login/login_screen.dart';
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/providers/providers.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Hive.initFlutter();
  await NotificationService.init();
  await BackgroundService.init();
  await BackgroundService.checkAndRegisterTask(); // Ensure background task is persisted
  await GoogleSignIn.instance.initialize();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Office Log',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: authState.when(
        data: (user) {
          if (user == null) return const LoginScreen();

          return Consumer(
            builder: (context, ref, child) {
              final userProfileAsync = ref.watch(userProfileProvider);
              return userProfileAsync.when(
                data: (profile) {
                  if (profile == null) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator.adaptive()),
                    );
                  }

                  if (profile.officeLocation == null ||
                      profile.officeLocation!.isEmpty) {
                    return const OnboardingScreen();
                  }
                  return const HomeScreen();
                },
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator.adaptive()),
                ),
                error: (e, s) =>
                    Scaffold(body: Center(child: Text('Error: $e'))),
              );
            },
          );
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        ),
        error: (err, stack) =>
            Scaffold(body: Center(child: Text('Error: $err'))),
      ),
    );
  }
}
