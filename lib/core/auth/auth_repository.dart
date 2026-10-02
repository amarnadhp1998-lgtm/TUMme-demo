import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final userDocumentProvider = StreamProvider.family<UserDocument?, String>((
  ref,
  uid,
) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.watchUserDocument(uid);
});

class UserDocument {
  const UserDocument({
    required this.onboardingCompleted,
    required this.displayName,
    required this.country,
    required this.timezone,
  });
  final bool onboardingCompleted;
  final String displayName;
  final String country;
  final String timezone;

  factory UserDocument.fromMap(Map<String, dynamic> data) => UserDocument(
    onboardingCompleted: data['onboardingCompleted'] == true,
    displayName: data['displayName'] as String? ?? '',
    country: data['country'] as String? ?? '',
    timezone: data['timezone'] as String? ?? 'Asia/Kolkata',
  );
}

class AuthRepository {
  const AuthRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Stream<User?> authStateChanges() => auth.userChanges();

  Stream<UserDocument?> watchUserDocument(String uid) async* {
    await ensureUserDocument(uid);
    yield* firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.data() == null
              ? null
              : UserDocument.fromMap(snapshot.data()!),
        );
  }

  Future<void> ensureUserDocument(String uid) async {
    final reference = firestore.collection('users').doc(uid);
    try {
      final cached = await reference.get(
        const GetOptions(source: Source.cache),
      );
      if (cached.exists) return;
    } on FirebaseException catch (_) {
      // A first sign-in has no cached user document.
    }
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) return;
      transaction.set(reference, {
        'displayName': auth.currentUser?.displayName ?? '',
        'country': '',
        'timezone': 'Asia/Kolkata',
        'unitSystem': 'metric',
        'onboardingVersion': 1,
        'onboardingCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> signIn(String email, String password) => auth
      .signInWithEmailAndPassword(email: email, password: password)
      .then((_) {});

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    if (kIsWeb) {
      await auth.signInWithPopup(provider);
    } else {
      await auth.signInWithProvider(provider);
    }
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    if (kIsWeb) {
      await auth.signInWithPopup(provider);
    } else {
      await auth.signInWithProvider(provider);
    }
  }

  Future<void> createAccount(String email, String password) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.sendEmailVerification();
  }

  Future<void> resendEmailVerification() async {
    final user = auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> refreshEmailVerification() async {
    await auth.currentUser?.reload();
    return auth.currentUser?.emailVerified == true;
  }

  Future<void> completeOnboarding({
    required String displayName,
    required String country,
    required String timezone,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    await user.updateDisplayName(displayName);
    await firestore.collection('users').doc(user.uid).update({
      'displayName': displayName.trim(),
      'country': country,
      'timezone': timezone,
      'unitSystem': 'metric',
      'onboardingCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email);
  Future<void> signOut() => auth.signOut();
}
