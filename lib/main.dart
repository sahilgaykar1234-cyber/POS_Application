import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/auth/auth_gate.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _startFirebase().timeout(const Duration(seconds: 20));
  } catch (e) {
    // Never leave a blank page: explain and offer a retry.
    runApp(StartupErrorApp(error: e));
    return;
  }

  // Offline cache. Settings can only be applied before Firestore is first
  // used; after a hot restart it is already running, so skip quietly.
  // (Safari private mode / Lockdown mode may refuse storage: also fine.)
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  } catch (_) {}

  try {
    await ThemeController.instance.load();
  } catch (_) {}

  runApp(const PosApp());
}

Future<void> _startFirebase() async {
  // Public web config of the registered "SuratPOS Web" app (safe to ship;
  // security comes from Auth + Firestore rules). Source:
  //   firebase apps:sdkconfig web --project suratpos
  // On a hot restart (web) the Firebase app is still alive: reuse it.
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDMe-TEEfwrfx7TH1bBVwqBQKuD_Zpabs0",
      appId: "1:696853288881:web:215140904c82a5c0a80f90",
      messagingSenderId: "696853288881",
      projectId: "suratpos",
      authDomain: "suratpos.firebaseapp.com",
      storageBucket: "suratpos.firebasestorage.app",
      measurementId: "G-LCG416QZTD",
    ),
  );
}

/// Shown instead of a blank page when the app cannot connect at start-up.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFC2410C)),
                  const SizedBox(height: 16),
                  const Text('Could not start Cafe POS', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    'Please check the internet connection and try again. On iPhone, '
                    'don\'t use Private browsing and turn off content blockers for this site.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => main(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 16),
                  Text('$error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themes = ThemeController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([themes, themes.legacyAdmin]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppConfig.appName,
        theme: themes.legacyAdmin.value ? AppTheme.legacyAdmin : AppTheme.light(),
        darkTheme: themes.legacyAdmin.value ? AppTheme.legacyAdmin : AppTheme.dark(),
        themeMode: themes.value,
        // Every role signs in here; AuthGate routes by server-assigned role.
        home: const AuthGate(),
      ),
    );
  }
}
