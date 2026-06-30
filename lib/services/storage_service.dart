import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../models/fixed_block.dart';
import '../models/day_label.dart';
import '../models/conversation_message.dart';
import '../models/sync_queue_item.dart';

enum SessionType { withoutAccount, account, noInternet }

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SessionType _currentSessionType = SessionType.withoutAccount;
  String _activeUserId = 'without_account';

  Box<Task>? _taskBox;
  Box<FixedBlock>? _fixedBlockBox;
  Box<DayLabel>? _dayLabelBox;
  Box<ConversationMessage>? _conversationBox;
  Box<SyncQueueItem>? _syncQueueBox;

  SessionType get currentSessionType => _currentSessionType;
  String get activeUserId => _activeUserId;

  Future<void> init() async {
    await Hive.initFlutter();

    _registerAdapterSafely(TaskAdapter());
    _registerAdapterSafely(FixedBlockAdapter());
    _registerAdapterSafely(DayLabelAdapter());
    _registerAdapterSafely(ConversationMessageAdapter());
    _registerAdapterSafely(SyncQueueItemAdapter());

    await switchSession(SessionType.withoutAccount, 'without_account');
  }

  void _registerAdapterSafely<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }
  }

  String _subdirName(SessionType type, String userId) {
    switch (type) {
      case SessionType.withoutAccount:
        return 'without_account';
      case SessionType.account:
        return 'account_$userId';
      case SessionType.noInternet:
        return 'no_internet_$userId';
    }
  }

  Future<String> _sessionBoxPath(String targetSubdirectory) async {
    if (kIsWeb) {
      return 'planmate_store/$targetSubdirectory';
    }

    final baseDir = await getApplicationDocumentsDirectory();
    return '${baseDir.path}/planmate_store/$targetSubdirectory';
  }

  Future<void> switchSession(SessionType type, String userId) async {
    await _closeAllBoxes();
    _currentSessionType = type;
    _activeUserId = userId;

    final targetSubdirectory = _subdirName(type, userId);

    try {
      final p = await _sessionBoxPath(targetSubdirectory);

      _taskBox = await Hive.openBox<Task>('tasks', path: p);
      _fixedBlockBox = await Hive.openBox<FixedBlock>('fixed_blocks', path: p);
      _dayLabelBox = await Hive.openBox<DayLabel>('day_labels', path: p);
      _conversationBox =
          await Hive.openBox<ConversationMessage>('conversation_history', path: p);

      if (type == SessionType.account) {
        _syncQueueBox = await Hive.openBox<SyncQueueItem>('sync_queue', path: p);
      } else {
        _syncQueueBox = null;
      }
    } catch (e) {
      debugPrint('StorageService: Failed to open boxes — $e');
    }

    notifyListeners();
  }

  Future<void> _closeAllBoxes() async {
    await _taskBox?.close();
    await _fixedBlockBox?.close();
    await _dayLabelBox?.close();
    await _conversationBox?.close();
    await _syncQueueBox?.close();
    _taskBox = null;
    _fixedBlockBox = null;
    _dayLabelBox = null;
    _conversationBox = null;
    _syncQueueBox = null;
  }

  // --- CRUD: Tasks ---
  List<Task> getTasks() {
    final box = _taskBox;
    if (box == null || !box.isOpen) return [];
    return box.values.toList();
  }

  Future<void> saveTask(Task task) async {
    await _taskBox?.put(task.id, task);
    _queueChange('create', 'tasks', task.toJson());
    notifyListeners();
  }

  Future<void> deleteTask(String taskId) async {
    final task = _taskBox?.get(taskId);
    if (task != null) {
      await _taskBox?.delete(taskId);
      _queueChange('delete', 'tasks', {'id': taskId});
      notifyListeners();
    }
  }

  // --- CRUD: Fixed Blocks ---
  List<FixedBlock> getFixedBlocks() {
    final box = _fixedBlockBox;
    if (box == null || !box.isOpen) return [];
    return box.values.toList();
  }

  Future<void> saveFixedBlock(FixedBlock block) async {
    await _fixedBlockBox?.put(block.id, block);
    _queueChange('create', 'schedule', block.toJson());
    notifyListeners();
  }

  Future<void> deleteFixedBlock(String blockId) async {
    await _fixedBlockBox?.delete(blockId);
    _queueChange('delete', 'schedule', {'id': blockId});
    notifyListeners();
  }

  // --- CRUD: Day Labels ---
  List<DayLabel> getDayLabels() {
    final box = _dayLabelBox;
    if (box == null || !box.isOpen) return [];
    return box.values.toList();
  }

  Future<void> saveDayLabel(DayLabel label) async {
    await _dayLabelBox?.put(label.date, label);
    _queueChange('create', 'schedule', label.toJson());
    notifyListeners();
  }

  Future<void> deleteDayLabel(String date) async {
    await _dayLabelBox?.delete(date);
    _queueChange('delete', 'schedule', {'date': date});
    notifyListeners();
  }

  // --- CRUD: Chat History ---
  List<ConversationMessage> getChatHistory() {
    final box = _conversationBox;
    if (box == null || !box.isOpen) return [];
    return box.values.toList();
  }

  Future<void> saveChatMessage(ConversationMessage msg) async {
    await _conversationBox?.put(msg.id, msg);
    notifyListeners();
  }

  Future<void> updateChatMessageStatus(
      String id, List<String> actionsExecuted) async {
    final existing = _conversationBox?.get(id);
    if (existing == null) return;
    await saveChatMessage(ConversationMessage(
      id: existing.id,
      timestamp: existing.timestamp,
      role: existing.role,
      text: existing.text,
      actionsExecuted: actionsExecuted,
    ));
  }

  Future<void> clearCurrentSessionData() async {
    await _taskBox?.clear();
    await _fixedBlockBox?.clear();
    await _dayLabelBox?.clear();
    await _conversationBox?.clear();
    await _syncQueueBox?.clear();
    notifyListeners();
  }

  Future<bool> guestSessionHasData() async {
    if (_currentSessionType == SessionType.withoutAccount) {
      return (_taskBox?.isNotEmpty ?? false) || (_fixedBlockBox?.isNotEmpty ?? false);
    }
    
    // We are in an account session. We must temporarily switch to guest to check,
    // otherwise opening a box named 'tasks' conflicts with the active account 'tasks' box.
    final prevType = _currentSessionType;
    final prevUser = _activeUserId;
    
    await switchSession(SessionType.withoutAccount, 'without_account');
    final hasData = (_taskBox?.isNotEmpty ?? false) || (_fixedBlockBox?.isNotEmpty ?? false);
    
    await switchSession(prevType, prevUser);
    return hasData;
  }

  /// Copies guest (without_account) data into the logged-in account session.
  /// Guest data on device is NOT deleted — user clears it manually if desired.
  Future<int> mergeGuestSessionIntoAccount(String accountUid) async {
    final List<Task> guestTasks = [];
    final List<FixedBlock> guestBlocks = [];
    final List<DayLabel> guestLabels = [];

    if (_currentSessionType == SessionType.withoutAccount) {
      guestTasks.addAll(getTasks());
      guestBlocks.addAll(getFixedBlocks());
      guestLabels.addAll(getDayLabels());
    } else {
      final prevType = _currentSessionType;
      final prevUser = _activeUserId;
      
      await switchSession(SessionType.withoutAccount, 'without_account');
      guestTasks.addAll(getTasks());
      guestBlocks.addAll(getFixedBlocks());
      guestLabels.addAll(getDayLabels());
      
      await switchSession(prevType, prevUser);
    }

    if (_currentSessionType != SessionType.account ||
        _activeUserId != accountUid) {
      await switchSession(SessionType.account, accountUid);
    }

    var imported = 0;
    for (final task in guestTasks) {
      await saveTask(task);
      imported++;
    }
    for (final block in guestBlocks) {
      await saveFixedBlock(block);
      imported++;
    }
    for (final label in guestLabels) {
      await saveDayLabel(label);
      imported++;
    }

    notifyListeners();
    return imported;
  }

  Future<void> clearConversationHistory() async {
    await _conversationBox?.clear();
    notifyListeners();
  }

  // --- Sync Queue ---
  List<SyncQueueItem> getSyncQueue() => _syncQueueBox?.values.toList() ?? [];

  Future<void> removeSyncQueueItem(String id) async {
    await _syncQueueBox?.delete(id);
  }

  void _queueChange(
      String operation, String collection, Map<String, dynamic> data) {
    if (_currentSessionType == SessionType.account && _syncQueueBox != null) {
      final itemId =
          'sync_${DateTime.now().millisecondsSinceEpoch}_${data['id'] ?? 'item'}';
      final queueItem = SyncQueueItem(
        id: itemId,
        timestamp: DateTime.now(),
        operation: operation,
        collection: collection,
        data: data,
      );
      _syncQueueBox?.put(itemId, queueItem);
    }
  }

  // --- Erase Session ---
  Future<void> eraseSessionData(SessionType type, String userId) async {
    final targetSubdirectory = _subdirName(type, userId);

    if (_currentSessionType == type && _activeUserId == userId) {
      await switchSession(SessionType.withoutAccount, 'without_account');
    }

    try {
      final sessionPath = await _sessionBoxPath(targetSubdirectory);
      for (final boxName in [
        'tasks',
        'fixed_blocks',
        'day_labels',
        'conversation_history',
        'sync_queue',
      ]) {
        if (await Hive.boxExists(boxName, path: sessionPath)) {
          await Hive.deleteBoxFromDisk(boxName, path: sessionPath);
        }
      }
    } catch (e) {
      debugPrint('StorageService: Failed to erase session — $e');
    }
  }
}
