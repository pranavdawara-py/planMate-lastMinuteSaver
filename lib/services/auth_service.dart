import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

/// Tracks a known account session on this device
class UserSessionProfile {
  final String uid;
  final String email;
  final bool isLoggedIn;
  final String lastUsed;

  UserSessionProfile({
    required this.uid,
    required this.email,
    required this.isLoggedIn,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'isLoggedIn': isLoggedIn,
        'lastUsed': lastUsed,
      };

  factory UserSessionProfile.fromJson(Map<String, dynamic> map) {
    return UserSessionProfile(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      isLoggedIn: map['isLoggedIn'] ?? false,
      lastUsed: map['lastUsed'] ?? DateTime.now().toIso8601String(),
    );
  }
}

class AuthService extends ChangeNotifier {
  AuthService(this._storageService) {
    _tryInitFirebase();
    _loadKnownProfiles();
  }

  final StorageService _storageService;

  FirebaseAuth? _firebaseAuth;
  bool _firebaseAvailable = false;

  String? _currentUid;
  String? _currentEmail;
  List<UserSessionProfile> _knownProfiles = [];
  bool _isLoading = false;

  String? get currentUid => _currentUid;
  String? get currentEmail => _currentEmail;
  bool get isLoggedIn => _currentUid != null && _currentEmail != null;
  bool get firebaseAvailable => _firebaseAvailable;
  List<UserSessionProfile> get knownProfiles => _knownProfiles;
  bool get isLoading => _isLoading;

  Future<void> _tryInitFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        _firebaseAvailable = false;
        debugPrint(
            'AuthService: Firebase not initialized — running in offline-only mode.');
        return;
      }

      _firebaseAuth = FirebaseAuth.instance;
      _firebaseAuth!.authStateChanges().listen(_onAuthStateChanged);
      _firebaseAvailable = true;
      debugPrint('AuthService: Firebase Auth ready.');
    } catch (e) {
      _firebaseAvailable = false;
      debugPrint('AuthService: Firebase init failed — $e');
    }
  }

  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      _currentUid = user.uid;
      _currentEmail = user.email ?? 'unknown@planmate.app';
      await _registerLocalProfile(_currentUid!, _currentEmail!, true);
      await _storageService.switchSession(SessionType.account, _currentUid!);
    } else {
      _currentUid = null;
      _currentEmail = null;
      await _storageService.switchSession(
          SessionType.withoutAccount, 'without_account');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    if (!_firebaseAvailable || _firebaseAuth == null) {
      throw Exception('Login requires Firebase. Firebase is not configured.');
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseAuth!
          .signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signUp(String email, String password) async {
    if (!_firebaseAvailable || _firebaseAuth == null) {
      throw Exception('Sign up requires Firebase. Firebase is not configured.');
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseAuth!
          .createUserWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    if (_currentUid != null) {
      await _registerLocalProfile(_currentUid!, _currentEmail ?? '', false);
    }
    if (_firebaseAvailable && _firebaseAuth != null) {
      await _firebaseAuth!.signOut();
    }
    _currentUid = null;
    _currentEmail = null;
    await _storageService.switchSession(
        SessionType.withoutAccount, 'without_account');
    _isLoading = false;
    notifyListeners();
  }

  Future<void> switchToSession(String uid) async {
    if (uid == 'without_account') {
      _currentUid = null;
      _currentEmail = null;
      await _storageService.switchSession(
          SessionType.withoutAccount, 'without_account');
    } else {
      final profile = _knownProfiles.firstWhere(
          (p) => p.uid == uid,
          orElse: () => UserSessionProfile(
              uid: uid, email: uid, isLoggedIn: false, lastUsed: ''));
      _currentUid = uid;
      _currentEmail = profile.email;
      await _storageService.switchSession(SessionType.account, uid);
    }
    notifyListeners();
  }

  Future<void> enterNoInternetMode(String targetUid) async {
    await _storageService.switchSession(SessionType.noInternet, targetUid);
    notifyListeners();
  }

  Future<int> mergeGuestDataIntoAccount() async {
    if (!isLoggedIn || _currentUid == null) {
      throw Exception('Sign in to an account before importing guest data.');
    }
    final count =
        await _storageService.mergeGuestSessionIntoAccount(_currentUid!);
    notifyListeners();
    return count;
  }

  Future<bool> guestWorkspaceHasData() => _storageService.guestSessionHasData();

  Future<void> clearActiveSessionData() async {
    await _storageService.clearCurrentSessionData();
    notifyListeners();
  }

  Future<void> _loadKnownProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileData = prefs.getStringList('planmate_cached_sessions') ?? [];
      _knownProfiles = profileData.map((jsonStr) {
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        return UserSessionProfile.fromJson(map);
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Failed to load profiles — $e');
    }
  }

  Future<void> _registerLocalProfile(
      String uid, String email, bool isLoggedIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _knownProfiles.removeWhere((p) => p.uid == uid);
      _knownProfiles.add(UserSessionProfile(
        uid: uid,
        email: email,
        isLoggedIn: isLoggedIn,
        lastUsed: DateTime.now().toIso8601String(),
      ));
      final encoded =
          _knownProfiles.map((p) => json.encode(p.toJson())).toList();
      await prefs.setStringList('planmate_cached_sessions', encoded);
      await _loadKnownProfiles();
    } catch (e) {
      debugPrint('AuthService: Failed to register profile — $e');
    }
  }

  Future<void> deleteSession(String uid) async {
    await _storageService.eraseSessionData(
      uid == 'without_account'
          ? SessionType.withoutAccount
          : SessionType.account,
      uid,
    );

    if (uid != 'without_account') {
      try {
        final prefs = await SharedPreferences.getInstance();
        _knownProfiles.removeWhere((p) => p.uid == uid);
        final encoded =
            _knownProfiles.map((p) => json.encode(p.toJson())).toList();
        await prefs.setStringList('planmate_cached_sessions', encoded);
      } catch (e) {
        debugPrint('AuthService: Failed to delete profile — $e');
      }
    }

    if (_currentUid == uid) {
      _currentUid = null;
      _currentEmail = null;
      await _storageService.switchSession(
          SessionType.withoutAccount, 'without_account');
    }

    await _loadKnownProfiles();
    notifyListeners();
  }
}
