import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/auth/app_user.dart';
import 'package:pos_app/core/config/app_config.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/core/widgets/message_screen.dart';
import 'package:pos_app/features/auth/login_screen.dart';

void main() {
  group('UserRole.fromClaim', () {
    test('parses the three roles', () {
      expect(UserRole.fromClaim('superAdmin'), UserRole.superAdmin);
      expect(UserRole.fromClaim('manager'), UserRole.manager);
      expect(UserRole.fromClaim('captain'), UserRole.captain);
    });
    test('unknown or missing role is null (no access)', () {
      expect(UserRole.fromClaim('admin'), isNull);
      expect(UserRole.fromClaim('Manager'), isNull);
      expect(UserRole.fromClaim(null), isNull);
    });
  });

  group('AppUser.fromClaims', () {
    AppUser build(Map<String, dynamic>? claims) =>
        AppUser.fromClaims(uid: 'u1', email: 'a@b.co', displayName: null, claims: claims);

    test('manager with cafe is valid', () {
      final u = build({'role': 'manager', 'cafeId': 'cafe1'});
      expect(u.isManager, isTrue);
      expect(u.cafeId, 'cafe1');
      expect(u.hasValidAssignment, isTrue);
      expect(u.displayName, 'a@b.co'); // falls back to email
    });

    test('super admin needs no cafe', () {
      final u = build({'role': 'superAdmin'});
      expect(u.isSuperAdmin, isTrue);
      expect(u.hasValidAssignment, isTrue);
    });

    test('manager/captain without cafe is NOT valid', () {
      expect(build({'role': 'manager'}).hasValidAssignment, isFalse);
      expect(build({'role': 'captain', 'cafeId': ''}).hasValidAssignment, isFalse);
    });

    test('no claims at all is NOT valid', () {
      expect(build(null).hasValidAssignment, isFalse);
      expect(build({}).role, isNull);
    });
  });

  group('username logins (must match tools/admin/lib/login.js)', () {
    test('username maps to Firebase account and 6+ char password', () {
      expect(AppConfig.loginEmail(' FlammyWood '), 'flammywood@pos.example.com');
      expect(AppConfig.loginPassword('flammywood', '123'), 'cafepos-123');
      expect(AppConfig.displayLogin('laforno@pos.example.com'), 'laforno');
    });
    test('email logins unchanged', () {
      expect(AppConfig.loginEmail('Owner@Gmail.com'), 'owner@gmail.com');
      expect(AppConfig.loginPassword('owner@gmail.com', 'secret12'), 'secret12');
    });
    test('validator accepts usernames and emails', () {
      expect(LoginValidators.usernameOrEmail('flammywood'), isNull);
      expect(LoginValidators.usernameOrEmail('laforno'), isNull);
      expect(LoginValidators.usernameOrEmail('a@b.co'), isNull);
      expect(LoginValidators.usernameOrEmail('ab'), isNotNull);
      expect(LoginValidators.usernameOrEmail('has space'), isNotNull);
      expect(LoginValidators.usernameOrEmail(''), isNotNull);
    });
  });

  group('LoginValidators', () {
    test('email', () {
      expect(LoginValidators.email(''), isNotNull);
      expect(LoginValidators.email('abc'), isNotNull);
      expect(LoginValidators.email('a@b'), isNotNull);
      expect(LoginValidators.email(' manager@cafe.in '), isNull);
    });
    test('password', () {
      expect(LoginValidators.password(''), isNotNull);
      expect(LoginValidators.password(null), isNotNull);
      expect(LoginValidators.password('x'), isNull);
    });
  });

  testWidgets('MessageScreen shows action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MessageScreen(
        icon: Icons.block,
        title: 'Blocked',
        message: 'Paused',
        actionLabel: 'Sign out',
        onAction: () => tapped = true,
      ),
    ));
    expect(find.text('Blocked'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    expect(tapped, isTrue);
  });
}
