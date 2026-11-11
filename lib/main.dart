import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/auth/auth_gate.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Public web config of the registered "SuratPOS Web" app (safe to ship;
  // security comes from Auth + Firestore rules). Source:
  //   firebase apps:sdkconfig web --project suratpos
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

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.dark,
      // Every role signs in here; AuthGate routes by server-assigned role.
      home: const AuthGate(),
    );
  }
}
