import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/auth/auth_gate.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Public web config of the registered "SuratPOS Web" app (safe to ship;
  // security comes from Auth + Firestore rules). Source:
  //   firebase apps:sdkconfig web --project suratpos
  // On a hot restart (web) the Firebase app is still alive: reuse it.
  if (Firebase.apps.isEmpty) {
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

  // Offline cache. Settings can only be applied before Firestore is first
  // used; after a hot restart it is already running, so skip quietly.
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  } catch (_) {}

  await ThemeController.instance.load();

  runApp(const PosApp());
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
