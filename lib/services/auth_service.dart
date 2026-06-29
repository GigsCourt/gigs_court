import 'package:firebase_auth/firebase_auth.dart';

class AuthResult {
  final bool success;
  final String? error;
  final User? user;

  AuthResult({required this.success, this.error, this.user});
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign In
  Future<AuthResult> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (!credential.user!.emailVerified) {
        await _auth.signOut();
        return AuthResult(
          success: false,
          error: 'Please verify your email before signing in.',
        );
      }

      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapError(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // Sign Up
  Future<AuthResult> signUp(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await credential.user!.sendEmailVerification();

      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapError(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // Resend verification email
  Future<AuthResult> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        return AuthResult(success: true);
      }
      return AuthResult(
        success: false,
        error: 'No user found. Please sign up again.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapError(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // Check if email is verified
  Future<AuthResult> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        final refreshedUser = _auth.currentUser;
        if (refreshedUser != null && refreshedUser.emailVerified) {
          return AuthResult(success: true, user: refreshedUser);
        }
        return AuthResult(
          success: false,
          error: 'Email not verified yet. Please check your inbox.',
        );
      }
      return AuthResult(
        success: false,
        error: 'No user found. Please sign up again.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // Forgot password
  Future<AuthResult> forgotPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _mapError(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Map Firebase error codes to custom messages
  String _mapError(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'invalid-email':
      case 'wrong-password':
        return 'Invalid email or password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Please sign in.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 8 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'requires-recent-login':
        return 'Please sign in again to continue.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}