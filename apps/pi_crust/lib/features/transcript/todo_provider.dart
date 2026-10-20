import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/session_state.dart';

class TodoItem {
  final int id;
  final String subject;
  final String status; // 'pending', 'in_progress', 'completed', 'deleted'
  final String? description;
  final String? activeForm;
  final List<int> blockedBy;
  final String? owner;

  const TodoItem({
    required this.id,
    required this.subject,
    this.status = 'pending',
    this.description,
    this.activeForm,
    this.blockedBy = const [],
    this.owner,
  });

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';
  bool get isPending => status == 'pending';
  bool get isDeleted => status == 'deleted';

  TodoItem copyWith({
    int? id,
    String? subject,
    String? status,
    String? description,
    String? activeForm,
    List<int>? blockedBy,
    String? owner,
  }) {
    return TodoItem(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      status: status ?? this.status,
      description: description ?? this.description,
      activeForm: activeForm ?? this.activeForm,
      blockedBy: blockedBy ?? this.blockedBy,
      owner: owner ?? this.owner,
    );
  }

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;
    final subject = map['subject']?.toString() ?? map['title']?.toString() ?? 'Task #$id';
    final status = map['status']?.toString().toLowerCase() ?? 'pending';
    final description = map['description']?.toString();
    final activeForm = map['activeForm']?.toString();
    final blockedByRaw = map['blockedBy'];
    final blockedBy = <int>[];
    if (blockedByRaw is List) {
      for (final b in blockedByRaw) {
        if (b is num) {
          blockedBy.add(b.toInt());
        } else if (b != null) {
          final p = int.tryParse(b.toString());
          if (p != null) {
            blockedBy.add(p);
          }
        }
      }
    }

    return TodoItem(
      id: id,
      subject: subject,
      status: status,
      description: description,
      activeForm: activeForm,
      blockedBy: blockedBy,
      owner: map['owner']?.toString(),
    );
  }
}

class TodoNotifier extends StateNotifier<List<TodoItem>> {
  final Ref ref;
  final String sessionId;
  ProviderSubscription? _subscription;

  TodoNotifier(this.ref, this.sessionId) : super([]) {
    _listenToSession();
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _listenToSession() {
    _subscription = ref.listen<SessionState>(
      sessionStateFamily(sessionId),
      (prev, next) {
        _syncFromSession(next);
      },
      fireImmediately: true,
    );
  }

  void _syncFromSession(SessionState sessionState) {
    final currentTasks = Map<int, TodoItem>.fromEntries(
      state.map((t) => MapEntry(t.id, t)),
    );

    // 1. Process historical entries
    for (final entry in sessionState.entries) {
      for (final tool in entry.toolCalls) {
        _processToolCall(tool, currentTasks);
      }
    }

    // 2. Process active tool calls in real time
    for (final tool in sessionState.activeToolCalls.values) {
      _processToolCall(tool, currentTasks);
    }

    // Filter out deleted tasks and sort by ID
    final updatedList = currentTasks.values
        .where((t) => !t.isDeleted)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (!_areListsEqual(state, updatedList)) {
      state = updatedList;
    }
  }

  void _processToolCall(ToolExecutionState tool, Map<int, TodoItem> tasks) {
    final name = tool.toolName.toLowerCase();
    if (name != 'todo' && name != 'todos' && name != 'task') {
      return;
    }

    // 1. Check details in output/result (authoritative snapshot from rpiv-todo)
    if (tool.output.isNotEmpty) {
      try {
        final decoded = jsonDecode(tool.output);
        if (decoded is Map<String, dynamic>) {
          final details = decoded['details'] ?? decoded;
          if (details is Map && details['tasks'] is List) {
            final list = details['tasks'] as List;
            for (final item in list) {
              if (item is Map) {
                final todo = TodoItem.fromMap(Map<String, dynamic>.from(item));
                tasks[todo.id] = todo;
              }
            }
            return;
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to args
    final args = tool.args;
    final action = args['action']?.toString().toLowerCase() ?? 'create';
    final rawId = args['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;
    final subject = args['subject']?.toString();
    final status = args['status']?.toString().toLowerCase();

    if (action == 'clear') {
      tasks.clear();
      return;
    }

    if (action == 'delete' && id > 0) {
      tasks.remove(id);
      return;
    }

    if (action == 'create') {
      final newId = id > 0 ? id : (tasks.isEmpty ? 1 : tasks.keys.reduce((a, b) => a > b ? a : b) + 1);
      final newSubject = subject ?? 'Nuovo task #$newId';
      final newStatus = status ?? 'pending';
      if (!tasks.containsKey(newId)) {
        tasks[newId] = TodoItem(
          id: newId,
          subject: newSubject,
          status: newStatus,
          description: args['description']?.toString(),
        );
      }
    } else if (action == 'update' && id > 0) {
      final existing = tasks[id];
      if (existing != null) {
        tasks[id] = existing.copyWith(
          subject: subject ?? existing.subject,
          status: status ?? existing.status,
          description: args['description']?.toString() ?? existing.description,
        );
      } else if (subject != null) {
        tasks[id] = TodoItem(
          id: id,
          subject: subject,
          status: status ?? 'pending',
          description: args['description']?.toString(),
        );
      }
    }
  }

  void toggleStatus(int id) {
    final updated = state.map((t) {
      if (t.id == id) {
        final newStatus = t.isCompleted ? 'pending' : 'completed';
        return t.copyWith(status: newStatus);
      }
      return t;
    }).toList();

    state = updated;

    // Optional: send steering message to daemon so agent is aware of manual toggle
    final client = ref.read(pcpClientProvider);
    if (client != null) {
      final task = updated.firstWhere((t) => t.id == id, orElse: () => state.first);
      final verb = task.isCompleted ? 'completato' : 'da fare (pending)';
      client.sendPrompt(
        sessionId,
        'Nota utente: il task #$id "${task.subject}" è stato contrassegnato come $verb.',
        streamingBehavior: 'steer',
      ).catchError((_) => <String, dynamic>{});
    }
  }

  void addTask(String subject) {
    if (subject.trim().isEmpty) return;
    final newId = state.isEmpty ? 1 : state.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
    final newItem = TodoItem(
      id: newId,
      subject: subject.trim(),
      status: 'pending',
    );
    state = [...state, newItem];

    final client = ref.read(pcpClientProvider);
    if (client != null) {
      client.sendPrompt(
        sessionId,
        'Nuovo task aggiunto dall\'utente: #$newId "${subject.trim()}".',
        streamingBehavior: 'steer',
      ).catchError((_) => <String, dynamic>{});
    }
  }

  bool _areListsEqual(List<TodoItem> a, List<TodoItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].subject != b[i].subject ||
          a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }
}

final todosFamily = StateNotifierProvider.autoDispose.family<TodoNotifier, List<TodoItem>, String>(
  (ref, sessionId) => TodoNotifier(ref, sessionId),
);
