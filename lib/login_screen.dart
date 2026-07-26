import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth.dart';
import 'settings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool signUp = false;
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();
  String? error;
  bool _obscure = true;

  @override
  void dispose() { _email.dispose(); _name.dispose(); _pass.dispose(); super.dispose(); }

  void _submit() {
    final auth = context.read<Auth>();
    final err = signUp
        ? auth.signUp(_email.text, _name.text, _pass.text)
        : auth.logIn(_email.text, _pass.text);
    setState(() => error = err);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<Settings>().accentColors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color.lerp(const Color(0xFF0A0A12), accent[0], 0.35)!, const Color(0xFF0A0A12)])),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 84, height: 84, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: accent)),
              child: const Icon(Icons.graphic_eq, size: 44, color: Colors.white)),
            const SizedBox(height: 18),
            const Text('Sound Circle', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(signUp ? 'Create your account' : 'Welcome back', textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 26),

            if (signUp) ...[
              _field(_name, 'Name', Icons.person_outline),
              const SizedBox(height: 12),
            ],
            _field(_email, 'Email', Icons.mail_outline, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field(_pass, 'Password', Icons.lock_outline, obscure: _obscure,
              suffix: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure))),

            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center)),

            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: accent[0]),
              onPressed: _submit,
              child: Text(signUp ? 'Sign up' : 'Log in', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() { signUp = !signUp; error = null; }),
              child: Text(signUp ? 'Have an account? Log in' : "New here? Create an account")),
            const Divider(height: 28),
            TextButton(
              onPressed: () => context.read<Auth>().continueAsGuest(),
              child: const Text('Continue as guest', style: TextStyle(color: Colors.white60))),
            const SizedBox(height: 6),
            const Text('Accounts are stored on this device for now.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white30)),
          ]),
        ))),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false, TextInputType? keyboard, Widget? suffix}) {
    return TextField(
      controller: c, obscureText: obscure, keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint, prefixIcon: Icon(icon), suffixIcon: suffix,
        filled: true, fillColor: const Color(0xFF16161f),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
    );
  }
}
