import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/auth/auth_gate.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Public web config (safe to ship; security comes from Auth + Firestore rules).
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDMe-TEEFwzfx7H1bBVwq8QKuD_Zpabs8",
      appId: "1:696863288881:web:216140984c82a5c8a00f90",
      messagingSenderId: "696853288881",
      projectId: "suratpos",
      authDomain: "suratpos.firebaseapp.com",
      storageBucket: "suratpos.appspot.com",
      measurementId: "G-LC3416JZYD",
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
