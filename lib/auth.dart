import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cloud accounts via Firebase Auth. Signing in on any device restores the same
/// account; the Library syncs its data to Firestore under the user's uid.
class Auth extends ChangeNotifier {
  final _fb = FirebaseAuth.instance;
  bool guest = false;
  SharedPreferences? _prefs;

  User? get _user => _fb.currentUser;
  String? get uid => _user?.uid;
  String? get email => _user?.email;
  String? get name => _user?.displayName;
  bool get signedIn => _user != null;
  bool get ready => signedIn || guest; // may enter the app

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    guest = _prefs?.getBool('auth_guest') ?? false;
    _fb.authStateChanges().listen((_) => notifyListeners());
    _fb.userChanges().listen((_) => notifyListeners());
    notifyListeners();
  }

  /// Returns null on success, otherwise a friendly error message.
  Future<String?> signUp(String email, String name, String password) async {
    email = email.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) return 'Enter a valid email';
    if (name.trim().isEmpty) return 'Enter your name';
    if (password.length < 6) return 'Password must be at least 6 characters';
    try {
      final cred = await _fb.createUserWithEmailAndPassword(email: email, password: password);
      await cred.user?.updateDisplayName(name.trim());
      await cred.user?.reload();
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid)
          .set({'name': name.trim(), 'email': email}, SetOptions(merge: true));
      guest = false; _prefs?.setBool('auth_guest', false);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (_) { return 'Something went wrong. Check your connection.'; }
  }

  Future<String?> logIn(String email, String password) async {
    email = email.trim().toLowerCase();
    try {
      await _fb.signInWithEmailAndPassword(email: email, password: password);
      guest = false; _prefs?.setBool('auth_guest', false);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e);
    } catch (_) { return 'Something went wrong. Check your connection.'; }
  }

  Future<void> updateName(String name) async {
    if (name.trim().isEmpty || _user == null) return;
    await _user!.updateDisplayName(name.trim());
    await _user!.reload();
    await FirebaseFirestore.instance.collection('users').doc(_user!.uid)
        .set({'name': name.trim()}, SetOptions(merge: true));
    notifyListeners();
  }

  void continueAsGuest() {
    guest = true;
    _prefs?.setBool('auth_guest', true);
    notifyListeners();
  }

  Future<void> logOut() async {
    await _fb.signOut();
    guest = false;
    _prefs?.setBool('auth_guest', false);
    notifyListeners();
  }

  String _msg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use': return 'That email already has an account';
      case 'invalid-email': return 'Enter a valid email';
      case 'weak-password': return 'Password is too weak';
      case 'user-not-found': return 'No account for that email';
      case 'wrong-password':
      case 'invalid-credential': return 'Wrong email or password';
      case 'network-request-failed': return 'No internet connection';
      case 'too-many-requests': return 'Too many attempts — try again later';
      default: return e.message ?? 'Authentication failed';
    }
  }
}
