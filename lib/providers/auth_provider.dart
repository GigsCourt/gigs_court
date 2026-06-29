import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AuthStatus {
  unknown,
  unauthenticated,
  emailNotVerified,
  setupIncomplete,
  authenticated,
}

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  AuthStatus _status = AuthStatus.unknown;
  User? _user;

  AuthStatus get status => _status;
  User? get user => _user;

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) {
    if (user == null) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _user = user;

    if (!user.emailVerified) {
      _status = AuthStatus.emailNotVerified;
      notifyListeners();
      return;
    }

    // Check if setup is complete — will be updated when we store user data in Firestore
    _status = AuthStatus.setupIncomplete;
    notifyListeners();
  }

  void setSetupComplete() {
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    await _auth.currentUser?.reload();
    _user = _auth.currentUser;
    if (_user != null && _user!.emailVerified && _status == AuthStatus.emailNotVerified) {
      _status = AuthStatus.setupIncomplete;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}