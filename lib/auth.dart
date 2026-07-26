import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A lightweight, on-device account system so the app has a real login/sign-up
/// flow. Accounts live only on this phone for now; when a backend is added this
/// same interface can point at a server API instead.
class Auth extends ChangeNotifier {
  String? email;
  String? name;
  String? avatarPath;
  bool guest = false;

  SharedPreferences? _prefs;

  bool get signedIn => email != null;
  bool get ready => signedIn || guest; // may enter the app

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    email = _prefs?.getString('auth_email');
    name = _prefs?.getString('auth_name');
    avatarPath = _prefs?.getString('auth_avatar');
    guest = _prefs?.getBool('auth_guest') ?? false;
    notifyListeners();
  }

  // FNV-1a — deterministic across runs (String.hashCode is not), one-way enough
  // for a local gate. Real password security arrives with the backend.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode('sc::$s')) { h ^= c; h = (h * 0x01000193) & 0xFFFFFFFF; }
    return h.toRadixString(16);
  }

  Map<String, dynamic> _accounts() {
    try { return (jsonDecode(_prefs?.getString('accounts') ?? '{}') as Map).cast<String, dynamic>(); }
    catch (_) { return {}; }
  }
  void _saveAccounts(Map<String, dynamic> a) => _prefs?.setString('accounts', jsonEncode(a));

  /// Returns null on success, otherwise an error message.
  String? signUp(String email, String name, String password) {
    email = email.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) return 'Enter a valid email';
    if (name.trim().isEmpty) return 'Enter your name';
    if (password.length < 4) return 'Password must be at least 4 characters';
    final accounts = _accounts();
    if (accounts.containsKey(email)) return 'That email already has an account';
    accounts[email] = {'name': name.trim(), 'pass': _hash(password)};
    _saveAccounts(accounts);
    _setSession(email, name.trim());
    return null;
  }

  String? logIn(String email, String password) {
    email = email.trim().toLowerCase();
    final accounts = _accounts();
    final a = accounts[email] as Map<String, dynamic>?;
    if (a == null) return 'No account for that email';
    if (a['pass'] != _hash(password)) return 'Wrong password';
    _setSession(email, (a['name'] ?? '') as String);
    return null;
  }

  void _setSession(String email, String name) {
    this.email = email; this.name = name; guest = false;
    _prefs?.setString('auth_email', email);
    _prefs?.setString('auth_name', name);
    _prefs?.setBool('auth_guest', false);
    notifyListeners();
  }

  void continueAsGuest() {
    guest = true;
    _prefs?.setBool('auth_guest', true);
    notifyListeners();
  }

  void updateProfile({String? name, String? avatar}) {
    if (name != null && name.trim().isNotEmpty) {
      this.name = name.trim();
      _prefs?.setString('auth_name', this.name!);
      if (email != null) {
        final accounts = _accounts();
        if (accounts[email] is Map) { (accounts[email] as Map)['name'] = this.name; _saveAccounts(accounts); }
      }
    }
    if (avatar != null) { avatarPath = avatar; _prefs?.setString('auth_avatar', avatar); }
    notifyListeners();
  }

  void logOut() {
    email = null; name = null; avatarPath = null; guest = false;
    _prefs?.remove('auth_email');
    _prefs?.remove('auth_name');
    _prefs?.remove('auth_avatar');
    _prefs?.setBool('auth_guest', false);
    notifyListeners();
  }
}
