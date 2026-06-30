import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'storage_service.dart';
import '../models/sync_queue_item.dart';

/// SyncService — drains the local sync queue to Firebase when internet returns.
class SyncService extends ChangeNotifier {
  SyncService(this._storageService);

  final StorageService _storageService;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;
  bool _isOnline = false;

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  void init() {
    _connectivity.checkConnectivity().then(_handleConnectivity);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_handleConnectivity);
  }

  void _handleConnectivity(dynamic result) {
    bool online = false;
    if (result is List<ConnectivityResult>) {
      online = result.isNotEmpty && !result.contains(ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      online = result != ConnectivityResult.none;
    }

    final wasOffline = !_isOnline;
    _isOnline = online;
    notifyListeners();

    if (online && wasOffline) {
      debugPrint('SyncService: Back online — attempting sync.');
      triggerQueueSync();
    }
  }

  String _firestoreCollection(SyncQueueItem item) {
    if (item.collection == 'tasks') return 'tasks';
    if (item.collection == 'schedule') {
      if (item.data.containsKey('date') && item.data.containsKey('label')) {
        return 'day_labels';
      }
      return 'fixed_blocks';
    }
    return item.collection;
  }

  String _documentId(SyncQueueItem item) {
    final data = item.data;
    if (data.containsKey('date') &&
        data.containsKey('label') &&
        !data.containsKey('startTime')) {
      return data['date'].toString();
    }
    return data['id']?.toString() ?? item.id;
  }

  Future<void> triggerQueueSync() async {
    if (!_firebaseReady) return;
    if (_storageService.currentSessionType != SessionType.account) return;
    if (_isSyncing) return;

    final queue = List<SyncQueueItem>.from(_storageService.getSyncQueue());
    if (queue.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    final activeUid = _storageService.activeUserId;
    debugPrint(
        'SyncService: Processing ${queue.length} sync items for $activeUid...');

    final firestore = FirebaseFirestore.instance;

    for (final SyncQueueItem item in queue) {
      try {
        final collection = _firestoreCollection(item);
        final docId = _documentId(item);
        final ref = firestore
            .collection('users')
            .doc(activeUid)
            .collection(collection)
            .doc(docId);

        switch (item.operation) {
          case 'create':
          case 'update':
            await ref.set(
              Map<String, dynamic>.from(item.data),
              SetOptions(merge: true),
            );
            break;
          case 'delete':
            await ref.delete();
            break;
        }

        await item.delete();
        debugPrint('SyncService: Synced ${item.id}');
      } catch (e) {
        debugPrint('SyncService: Failed on ${item.id} — $e. Stopping.');
        break;
      }
    }

    _isSyncing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
