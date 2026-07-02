import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthStatus {
  unknown,
  unauthenticated,
  emailNotVerified,
  setupIncomplete,
  authenticated,
}

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _isEarlyAccess = true;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get isEarlyAccess => _isEarlyAccess;

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void setEarlyAccess(bool value) {
    _isEarlyAccess = value;
    notifyListeners();
  }

  Future<void> _onAuthStateChanged(User? user) async {
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

    // Check Firestore if setup is already completed
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['setupComplete'] == true) {
        _status = AuthStatus.authenticated;
        notifyListeners();
        return;
      }
    } catch (_) {
      // If Firestore check fails, default to setupIncomplete
    }

    _status = AuthStatus.setupIncomplete;
    notifyListeners();
  }

  Future<void> setSetupComplete() async {
    _status = AuthStatus.authenticated;
    notifyListeners();

    // Save to Firestore so it survives app restarts
    try {
      await _firestore.collection('users').doc(_user?.uid).set({
        'setupComplete': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // Silently fail — status is already set in memory
    }
  }

  Future<void> refreshUser() async {
    await _auth.currentUser?.reload();
    _user = _auth.currentUser;
    if (_user != null &&
        _user!.emailVerified &&
        _status == AuthStatus.emailNotVerified) {
      // Re-check Firestore on refresh
      try {
        final doc =
            await _firestore.collection('users').doc(_user!.uid).get();
        if (doc.exists && doc.data()?['setupComplete'] == true) {
          _status = AuthStatus.authenticated;
        } else {
          _status = AuthStatus.setupIncomplete;
        }
      } catch (_) {
        _status = AuthStatus.setupIncomplete;
      }
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
