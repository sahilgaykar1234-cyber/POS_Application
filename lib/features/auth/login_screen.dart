import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_logo.dart';

/// Form validators, kept public so they can be unit-tested.
class LoginValidators {
  LoginValidators._();

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your email';
    if (!_email.hasMatch(s)) return 'Please enter a valid email';
    return null;
  }

  static final RegExp _username = RegExp(r'^[a-zA-Z0-9._-]{3,30}$');

  /// Username (e.g. "flammywood") or email.
  static String? usernameOrEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your username';
    if (s.contains('@')) return email(s);
    if (!_username.hasMatch(s)) return 'Username: 3–30 letters/numbers';
    return null;
  }

  static String? password(String? v) {
    if ((v ?? '').isEmpty) return 'Please enter your password';
    return null;
  }
}

/// Single sign-in screen for every role. After sign-in, [AuthGate] reads the
/// user's role from the server and opens the right dashboard.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn(identifier: _emailCtrl.text, password: _passwordCtrl.text);
      // AuthGate reacts to the auth change and navigates.
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.contains('@') ? _emailCtrl.text.trim() : '');
    final formKey = GlobalKey<FormState>();

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your account email. We will send you a link to set a new password.\n\n'
                'If you sign in with a username (not an email), please ask the owner to reset your password.',
                style: TextStyle(color: ctx.palette.inkMuted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                validator: LoginValidators.email,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (email == null || !mounted) return;

    try {
      await AuthService.instance.sendPasswordResetEmail(email);
    } catch (_) {
      // Ignore: we show the same message either way so nobody can use this
      // screen to discover which emails have accounts.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('If an account exists for that email, a reset link has been sent. Check your inbox and spam folder.'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = MediaQuery.sizeOf(context).width >= 960;

    final form = Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 48)),
              const SizedBox(height: Space.xl),
            ],
            Text('Welcome back', style: context.text.headlineMedium),
            const SizedBox(height: 4),
            Text('Sign in with your cafe username or email.', style: TextStyle(color: p.inkSubtle)),
            const SizedBox(height: Space.xl),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              textInputAction: TextInputAction.next,
              enabled: !_loading,
              validator: LoginValidators.usernameOrEmail,
              decoration: const InputDecoration(labelText: 'Username', hintText: 'Enter your username', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              enabled: !_loading,
              validator: LoginValidators.password,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _loading ? null : _forgotPassword, child: const Text('Forgot password?')),
            ),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: p.dangerTint, borderRadius: Radii.controlR),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: p.danger, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(_error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );

    final formPane = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: form),
      ),
    );

    if (!wide) return Scaffold(backgroundColor: p.surface, body: SafeArea(child: formPane));

    return Scaffold(
      backgroundColor: p.surface,
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: p.ink,
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const AppLogo(size: 40),
                    const SizedBox(width: Space.md),
                    Text(AppConfig.appName, style: TextStyle(color: p.surface, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  const Spacer(),
                  Text('Run your cafe from one screen.',
                      style: TextStyle(color: p.surface, fontSize: 40, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: Space.lg),
                  for (final f in const [
                    'Take orders and bill in seconds',
                    'Live table and kitchen status',
                    'Menu, staff and sales reports in one place',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Row(children: [
                        Icon(Icons.check_circle_rounded, color: p.primary, size: 20),
                        const SizedBox(width: Space.sm),
                        Text(f, style: TextStyle(color: p.border, fontSize: 16)),
                      ]),
                    ),
                  const Spacer(),
                  Text(AppConfig.appTagline, style: TextStyle(color: p.inkSubtle, fontSize: 13)),
                ],
              ),
            ),
          ),
          Expanded(child: formPane),
        ],
      ),
    );
  }
}
