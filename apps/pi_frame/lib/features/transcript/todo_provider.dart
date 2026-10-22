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
  final Map<String, int> _toolCallIdToTaskId = {};
  final Map<int, TodoItem> _userManualTasks = {};
  final Map<int, String> _userStatusOverrides = {};
  int _nextGeneratedId = 1;

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
    final currentTasks = <int, TodoItem>{};

    // 1. Add user manual tasks
    for (final manualTask in _userManualTasks.values) {
      currentTasks[manualTask.id] = manualTask;
    }

    // 2. Process historical entries
    for (final entry in sessionState.entries) {
      if (entry.text.isNotEmpty &&
          (entry.text.contains('Updated #') ||
              entry.text.contains('Updated task') ||
              entry.text.contains('->') ||
              entry.text.contains('activeForm') ||
              entry.text.contains('status:') ||
              entry.text.contains('"status"') ||
              entry.text.contains('nextId:'))) {
        _extractTasksFromText(entry.text, currentTasks);
      }
      for (final tool in entry.toolCalls) {
        _processToolCall(tool, currentTasks);
      }
    }

    // 3. Process active tool calls in real time
    for (final tool in sessionState.activeToolCalls.values) {
      _processToolCall(tool, currentTasks);
    }

    // 4. Process streaming text in real time
    for (final text in sessionState.streamingTextBlocks.values) {
      if (text.isNotEmpty &&
          (text.contains('Updated #') ||
              text.contains('Updated task') ||
              text.contains('->') ||
              text.contains('activeForm') ||
              text.contains('status:') ||
              text.contains('"status"') ||
              text.contains('nextId:'))) {
        _extractTasksFromText(text, currentTasks);
      }
    }

    // 5. Apply user status overrides
    for (final overrideEntry in _userStatusOverrides.entries) {
      final task = currentTasks[overrideEntry.key];
      if (task != null) {
        currentTasks[overrideEntry.key] = task.copyWith(status: overrideEntry.value);
      }
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

  bool _isTodoTool(ToolExecutionState tool) {
    final name = tool.toolName.toLowerCase();
    if (name == 'todo' || name == 'todos' || name == 'tasks') return true;
    if (name == 'task' || name.contains('todo') || name.contains('task')) {
      // Treat as todo tool if it has todo-like args or output
      if (tool.args.containsKey('action') ||
          tool.args.containsKey('subject') ||
          tool.args.containsKey('todos') ||
          tool.args.containsKey('tasks') ||
          (tool.args.containsKey('status') && tool.args.containsKey('id'))) {
        return true;
      }
      final out = tool.output;
      if (out.contains('tasks') ||
          out.contains('details') ||
          out.contains('activeForm') ||
          out.contains('nextId') ||
          (out.contains('id') && out.contains('status'))) {
        return true;
      }
    }
    return false;
  }

  void _extractTasksFromText(String rawText, Map<int, TodoItem> tasks) {
    if (rawText.isEmpty) return;

    // 1. First attempt JSON decode if structured
    if (rawText.contains('{') || rawText.contains('[')) {
      try {
        final decoded = jsonDecode(rawText);
        if (decoded is Map<String, dynamic>) {
          final details = decoded['details'] ?? decoded;
          final dynamic rawList = details is Map
              ? (details['tasks'] ?? details['todos'])
              : null;
          if (rawList is List) {
            for (final item in rawList) {
              if (item is Map) {
                final todo = TodoItem.fromMap(Map<String, dynamic>.from(item));
                _mergeOrAddTask(tasks, todo);
              }
            }
            return;
          }
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && (item.containsKey('id') || item.containsKey('subject'))) {
              final todo = TodoItem.fromMap(Map<String, dynamic>.from(item));
              _mergeOrAddTask(tasks, todo);
            }
          }
          return;
        }
      } catch (_) {}
    }

    // 2. Robust regex extraction for unquoted / relaxed object notation:
    // e.g. {id: 2, subject: ..., status: completed, description: ..., activeForm: ...}
    final idMatches = RegExp(r"""\{(?:\s*['"]?id['"]?\s*:\s*(\d+))""").allMatches(rawText).toList();
    if (idMatches.isNotEmpty) {
      for (int i = 0; i < idMatches.length; i++) {
        final startIdx = idMatches[i].start;
        final endIdx = (i + 1 < idMatches.length)
            ? idMatches[i + 1].start
            : rawText.length;
        var block = rawText.substring(startIdx, endIdx);
        final closeIdx = block.lastIndexOf('}');
        if (closeIdx != -1) {
          block = block.substring(0, closeIdx + 1);
        }

        final idStr = RegExp(r"""['"]?id['"]?\s*:\s*(\d+)""").firstMatch(block)?.group(1);
        final id = idStr != null ? int.tryParse(idStr) ?? 0 : 0;
        if (id <= 0) continue;

        final statusRaw = RegExp(r"""['"]?status['"]?\s*:\s*['"]?([a-zA-Z0-9_-]+)['"]?""")
            .firstMatch(block)
            ?.group(1);
        final status = _normalizeStatus(statusRaw);

        String? extractField(String key) {
          final pattern = "['\"]?$key"
              r"""['"]?\s*:\s*['"]?((?:(?!\s*,\s*['"]?(?:id|status|subject|title|description|activeForm|blockedBy|owner|metadata|nextId)['"]?\s*:).)+)""";
          final m = RegExp(pattern, dotAll: true).firstMatch(block);
          var val = m?.group(1)?.trim();
          if (val == null) return null;
          if (val.endsWith('}')) val = val.substring(0, val.length - 1).trim();
          if (val.endsWith(',')) val = val.substring(0, val.length - 1).trim();
          if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
            val = val.substring(1, val.length - 1);
          } else if (val.startsWith("'") && val.endsWith("'") && val.length >= 2) {
            val = val.substring(1, val.length - 1);
          }
          return val.isNotEmpty ? val : null;
        }

        final subject = extractField('subject') ?? extractField('title');
        final description = extractField('description');
        final activeForm = extractField('activeForm');
        final owner = extractField('owner');

        final item = TodoItem(
          id: id,
          subject: subject ?? tasks[id]?.subject ?? 'Task #$id',
          status: status ?? tasks[id]?.status ?? 'pending',
          description: description ?? tasks[id]?.description,
          activeForm: activeForm ?? tasks[id]?.activeForm,
          owner: owner ?? tasks[id]?.owner,
        );

        _mergeOrAddTask(tasks, item);
      }
    }

    // 3. Regex extraction for task status transitions, e.g.:
    // "Updated #36 (in_progress -> completed)"
    // "Updated task #36 (in_progress -> completed)"
    // "#36 (in_progress -> completed)"
    // "Task #36 marked as completed"
    final transitionMatches = RegExp(
      r'(?:Updated|Update|Task|Marked)?\s*(?:task\s*)?#(\d+)\s*(?:\((?:[^->\n]+)\s*->\s*([^)\n]+)\)|:\s*(?:[^->\n]+)\s*->\s*([^\n]+)|(?:as|to)\s+([a-zA-Z_-]+))',
      caseSensitive: false,
    ).allMatches(rawText);

    for (final match in transitionMatches) {
      final idStr = match.group(1);
      final rawStatus = match.group(2) ?? match.group(3) ?? match.group(4);
      if (idStr != null && rawStatus != null) {
        final id = int.tryParse(idStr);
        final status = _normalizeStatus(rawStatus);
        if (id != null && id > 0 && status != null) {
          final existing = tasks[id];
          if (existing != null) {
            tasks[id] = existing.copyWith(status: status);
          } else {
            tasks[id] = TodoItem(
              id: id,
              subject: 'Task #$id',
              status: status,
            );
          }
        }
      }
    }
  }

  void _mergeOrAddTask(Map<int, TodoItem> tasks, TodoItem incoming) {
    final existing = tasks[incoming.id];
    if (existing == null) {
      tasks[incoming.id] = incoming;
    } else {
      tasks[incoming.id] = existing.copyWith(
        subject: incoming.subject.isNotEmpty ? incoming.subject : existing.subject,
        status: incoming.status,
        description: incoming.description ?? existing.description,
        activeForm: incoming.activeForm ?? existing.activeForm,
        owner: incoming.owner ?? existing.owner,
        blockedBy: incoming.blockedBy.isNotEmpty ? incoming.blockedBy : existing.blockedBy,
      );
    }
  }

  String? _normalizeStatus(String? raw) {
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'completed' || lower == 'done' || lower == 'closed' || lower == 'finished') {
      return 'completed';
    }
    if (lower == 'in_progress' || lower == 'inprogress' || lower == 'running' || lower == 'working') {
      return 'in_progress';
    }
    if (lower == 'pending' || lower == 'todo' || lower == 'open') {
      return 'pending';
    }
    return lower;
  }

  void _processToolCall(ToolExecutionState tool, Map<int, TodoItem> tasks) {
    if (tool.output.isNotEmpty) {
      _extractTasksFromText(tool.output, tasks);
    }

    if (!_isTodoTool(tool)) {
      return;
    }

    // Fallback to args
    final args = tool.args;
    final action = args['action']?.toString().toLowerCase();
    final rawId = args['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '0') ?? 0;
    final subject = args['subject']?.toString() ?? args['title']?.toString();
    final status = _normalizeStatus(args['status']?.toString());

    // Direct status update when id and status are provided
    if (id > 0 && status != null && (action == null || action == 'update')) {
      final existing = tasks[id];
      if (existing != null) {
        tasks[id] = existing.copyWith(
          status: status,
          subject: subject ?? existing.subject,
          description: args['description']?.toString() ?? existing.description,
        );
      } else {
        tasks[id] = TodoItem(
          id: id,
          subject: subject ?? 'Task #$id',
          status: status,
          description: args['description']?.toString(),
        );
      }
      return;
    }

    // If neither action nor subject is provided, do not treat as a todo command
    if (action == null && subject == null) {
      return;
    }

    final effectiveAction = action ?? 'create';

    if (effectiveAction == 'clear') {
      tasks.clear();
      return;
    }

    if (effectiveAction == 'delete' && id > 0) {
      tasks.remove(id);
      return;
    }

    if (effectiveAction == 'create' || effectiveAction == 'add') {
      final int taskId;
      if (id > 0) {
        taskId = id;
      } else {
        taskId = _toolCallIdToTaskId.putIfAbsent(tool.toolCallId, () {
          while (tasks.containsKey(_nextGeneratedId) || _userManualTasks.containsKey(_nextGeneratedId)) {
            _nextGeneratedId++;
          }
          return _nextGeneratedId++;
        });
      }
      final newSubject = subject ?? 'Nuovo task #$taskId';
      final newStatus = status ?? 'pending';
      tasks[taskId] = TodoItem(
        id: taskId,
        subject: newSubject,
        status: newStatus,
        description: args['description']?.toString(),
      );
    } else if ((effectiveAction == 'update' || effectiveAction == 'toggle') && id > 0) {
      final existing = tasks[id];
      if (existing != null) {
        tasks[id] = existing.copyWith(
          subject: subject ?? existing.subject,
          status: status ?? (effectiveAction == 'toggle' ? (existing.isCompleted ? 'pending' : 'completed') : existing.status),
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
    final task = state.firstWhere(
      (t) => t.id == id,
      orElse: () => TodoItem(id: id, subject: ''),
    );
    final newStatus = task.isCompleted ? 'pending' : 'completed';
    _userStatusOverrides[id] = newStatus;

    if (_userManualTasks.containsKey(id)) {
      _userManualTasks[id] = _userManualTasks[id]!.copyWith(status: newStatus);
    }

    final updated = state.map((t) {
      if (t.id == id) {
        return t.copyWith(status: newStatus);
      }
      return t;
    }).toList();

    state = updated;

    // Optional: send steering message to daemon so agent is aware of manual toggle
    final client = ref.read(pcpClientProvider);
    if (client != null) {
      final verb = newStatus == 'completed' ? 'completato' : 'da fare (pending)';
      client.sendPrompt(
        sessionId,
        'Nota utente: il task #$id "${task.subject}" è stato contrassegnato come $verb.',
        streamingBehavior: 'steer',
      ).catchError((_) => <String, dynamic>{});
    }
  }

  void addTask(String subject) {
    final trimmed = subject.trim();
    if (trimmed.isEmpty) return;

    while (state.any((t) => t.id == _nextGeneratedId) || _userManualTasks.containsKey(_nextGeneratedId)) {
      _nextGeneratedId++;
    }
    final newId = _nextGeneratedId++;
    final newItem = TodoItem(
      id: newId,
      subject: trimmed,
      status: 'pending',
    );
    _userManualTasks[newId] = newItem;
    state = [...state, newItem]..sort((a, b) => a.id.compareTo(b.id));

    final client = ref.read(pcpClientProvider);
    if (client != null) {
      client.sendPrompt(
        sessionId,
        'Nuovo task aggiunto dall\'utente: #$newId "$trimmed".',
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
