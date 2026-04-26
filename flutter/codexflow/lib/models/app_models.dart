import 'dart:math' as math;

import 'package:intl/intl.dart';

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value
        .map((key, dynamic innerValue) => MapEntry(key.toString(), innerValue));
  }
  return <String, dynamic>{};
}

List<dynamic> asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
  }
  return fallback;
}

DateTime parseDateTime(Object? value) {
  final raw = asString(value);
  if (raw.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(raw)?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

class UploadedImageRef {
  UploadedImageRef({
    required this.id,
    required this.name,
    required this.size,
  });

  final String id;
  final String name;
  final int size;

  factory UploadedImageRef.fromJson(Map<String, dynamic> json) {
    return UploadedImageRef(
      id: asString(json['id']),
      name: asString(json['name']),
      size: asInt(json['size']),
    );
  }
}

class DashboardResponse {
  DashboardResponse({
    required this.agent,
    required this.agents,
    required this.defaultAgent,
    required this.stats,
    required this.sessions,
    required this.approvals,
  });

  final AgentSnapshot agent;
  final List<AgentOption> agents;
  final String defaultAgent;
  final DashboardStats stats;
  final List<SessionSummary> sessions;
  final List<PendingRequestView> approvals;

  factory DashboardResponse.fromJson(Map<String, dynamic> json) {
    return DashboardResponse(
      agent: AgentSnapshot.fromJson(asMap(json['agent'])),
      agents: asList(json['agents'])
          .map((item) => AgentOption.fromJson(asMap(item)))
          .toList(),
      defaultAgent: asString(json['defaultAgent'], 'codex'),
      stats: DashboardStats.fromJson(asMap(json['stats'])),
      sessions: asList(json['sessions'])
          .map((item) => SessionSummary.fromJson(asMap(item)))
          .toList(),
      approvals: asList(json['approvals'])
          .map((item) => PendingRequestView.fromJson(asMap(item)))
          .toList(),
    );
  }

  factory DashboardResponse.placeholder() {
    return DashboardResponse(
      agent: AgentSnapshot(
        connected: false,
        startedAt: DateTime.now(),
        listenAddr: '',
        codexBinaryPath: 'codex',
      ),
      agents: <AgentOption>[
        AgentOption(
          id: 'codex',
          name: 'Codex',
          available: true,
          isDefault: true,
          capabilities: AgentCapabilities(
            supportsInterruptTurn: true,
            supportsApprovals: true,
            supportsArchive: true,
            supportsResume: true,
            supportsHistoryImport: false,
          ),
        ),
        AgentOption(
          id: 'claude',
          name: 'Claude Code',
          available: false,
          isDefault: false,
          capabilities: AgentCapabilities(
            supportsInterruptTurn: true,
            supportsApprovals: true,
            supportsArchive: true,
            supportsResume: true,
            supportsHistoryImport: true,
          ),
        ),
      ],
      defaultAgent: 'codex',
      stats: DashboardStats(
        totalSessions: 0,
        loadedSessions: 0,
        activeSessions: 0,
        pendingApprovals: 0,
      ),
      sessions: const <SessionSummary>[],
      approvals: const <PendingRequestView>[],
    );
  }
}

class AgentOption {
  AgentOption({
    required this.id,
    required this.name,
    required this.available,
    required this.isDefault,
    required this.capabilities,
  });

  final String id;
  final String name;
  final bool available;
  final bool isDefault;
  final AgentCapabilities capabilities;

  factory AgentOption.fromJson(Map<String, dynamic> json) {
    return AgentOption(
      id: asString(json['id']),
      name: asString(json['name']),
      available: asBool(json['available']),
      isDefault: asBool(json['default']),
      capabilities: AgentCapabilities.fromJson(asMap(json['capabilities'])),
    );
  }
}

class AgentCapabilities {
  AgentCapabilities({
    required this.supportsInterruptTurn,
    required this.supportsApprovals,
    required this.supportsArchive,
    required this.supportsResume,
    required this.supportsHistoryImport,
  });

  final bool supportsInterruptTurn;
  final bool supportsApprovals;
  final bool supportsArchive;
  final bool supportsResume;
  final bool supportsHistoryImport;

  factory AgentCapabilities.fromJson(Map<String, dynamic> json) {
    return AgentCapabilities(
      supportsInterruptTurn: asBool(json['supportsInterruptTurn']),
      supportsApprovals: asBool(json['supportsApprovals']),
      supportsArchive: asBool(json['supportsArchive']),
      supportsResume: asBool(json['supportsResume']),
      supportsHistoryImport: asBool(json['supportsHistoryImport']),
    );
  }
}

class AgentSnapshot {
  AgentSnapshot({
    required this.connected,
    required this.startedAt,
    required this.listenAddr,
    required this.codexBinaryPath,
  });

  final bool connected;
  final DateTime startedAt;
  final String listenAddr;
  final String codexBinaryPath;

  factory AgentSnapshot.fromJson(Map<String, dynamic> json) {
    return AgentSnapshot(
      connected: asBool(json['connected']),
      startedAt: parseDateTime(json['startedAt']),
      listenAddr: asString(json['listenAddr']),
      codexBinaryPath: asString(json['codexBinaryPath']),
    );
  }
}

class DashboardStats {
  DashboardStats({
    required this.totalSessions,
    required this.loadedSessions,
    required this.activeSessions,
    required this.pendingApprovals,
  });

  final int totalSessions;
  final int loadedSessions;
  final int activeSessions;
  final int pendingApprovals;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalSessions: asInt(json['totalSessions']),
      loadedSessions: asInt(json['loadedSessions']),
      activeSessions: asInt(json['activeSessions']),
      pendingApprovals: asInt(json['pendingApprovals']),
    );
  }
}

class SessionSummary {
  SessionSummary({
    required this.id,
    required this.agentId,
    required this.name,
    required this.preview,
    required this.cwd,
    required this.source,
    required this.status,
    required this.activeFlags,
    required this.loaded,
    required this.updatedAt,
    required this.createdAt,
    required this.modelProvider,
    required this.branch,
    required this.pendingApprovals,
    required this.lastTurnId,
    required this.lastTurnStatus,
    required this.agentNickname,
    required this.agentRole,
    required this.lifecycleStage,
    required this.historyAvailable,
    required this.runtimeAvailable,
    required this.runtimeAttachMode,
    required this.resumeAvailable,
    required this.resumeBlockedReason,
    required this.ended,
  });

  final String id;
  final String agentId;
  final String name;
  final String preview;
  final String cwd;
  final String source;
  final String status;
  final List<String> activeFlags;
  final bool loaded;
  final int updatedAt;
  final int createdAt;
  final String modelProvider;
  final String branch;
  final int pendingApprovals;
  final String lastTurnId;
  final String lastTurnStatus;
  final String agentNickname;
  final String agentRole;
  final String lifecycleStage;
  final bool historyAvailable;
  final bool runtimeAvailable;
  final String runtimeAttachMode;
  final bool resumeAvailable;
  final String resumeBlockedReason;
  final bool ended;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: asString(json['id']),
      agentId: asString(json['agentId'], 'codex'),
      name: asString(json['name']),
      preview: asString(json['preview']),
      cwd: asString(json['cwd']),
      source: asString(json['source']),
      status: asString(json['status']),
      activeFlags:
          asList(json['activeFlags']).map((item) => asString(item)).toList(),
      loaded: asBool(json['loaded']),
      updatedAt: asInt(json['updatedAt']),
      createdAt: asInt(json['createdAt']),
      modelProvider: asString(json['modelProvider']),
      branch: asString(json['branch']),
      pendingApprovals: asInt(json['pendingApprovals']),
      lastTurnId: asString(json['lastTurnId']),
      lastTurnStatus: asString(json['lastTurnStatus']),
      agentNickname: asString(json['agentNickname']),
      agentRole: asString(json['agentRole']),
      lifecycleStage: asString(json['lifecycleStage']),
      historyAvailable: asBool(json['historyAvailable']),
      runtimeAvailable: asBool(json['runtimeAvailable']),
      runtimeAttachMode: asString(json['runtimeAttachMode']),
      resumeAvailable: asBool(json['resumeAvailable'], true),
      resumeBlockedReason: asString(json['resumeBlockedReason']),
      ended: asBool(json['ended']),
    );
  }

  String get displayName {
    final explicitName = _normalizedTitle(name);
    if (explicitName != null) {
      return explicitName;
    }
    final nickname = _normalizedTitle(agentNickname);
    if (nickname != null) {
      return nickname;
    }
    final directoryName = _directoryName;
    if (directoryName != null) {
      return directoryName;
    }
    final previewTitle = _previewTitle;
    if (previewTitle != null) {
      return previewTitle;
    }
    return 'Session ${id.substring(0, math.min(8, id.length))}';
  }

  String get previewSummary => _normalizedPreview(preview);

  String get previewExcerpt => _normalizedText(preview).headTailTruncated(
        maxLength: 220,
        head: 140,
        tail: 72,
      );

  String get updatedAtDisplay => formattedTimestamp(updatedAt);

  bool get isActive => status == 'active';

  bool get isEnded => ended;

  bool get canResume => resumeAvailable;

  bool get isClaudeSession => agentId == 'claude';

  bool get isRuntimeDiscoverable => runtimeAvailable;

  bool get isHistoryDiscoverable => historyAvailable;

  bool get isManagedStage => lifecycleStage == 'managed';

  bool get hasWaitingState =>
      activeFlags.contains('waitingOnApproval') ||
      activeFlags.contains('waitingOnUserInput');

  String formattedTimestamp(int timestamp) {
    if (timestamp <= 0) {
      return '未知';
    }

    final date =
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == date.year &&
        yesterday.month == date.month &&
        yesterday.day == date.day;

    if (sameDay) {
      return '今天 ${DateFormat('HH:mm').format(date)}';
    }
    if (isYesterday) {
      return '昨天 ${DateFormat('HH:mm').format(date)}';
    }
    if (now.year == date.year) {
      return DateFormat('MM-dd HH:mm').format(date);
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  String? _normalizedTitle(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get _directoryName {
    final trimmed = cwd.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final pieces = normalized.split('/');
    final component = pieces.isEmpty ? '' : pieces.last.trim();
    return component.isEmpty ? null : component;
  }

  String? get _previewTitle {
    final cleaned = _normalizedPreview(preview);
    if (cleaned.isEmpty) {
      return null;
    }
    if (cleaned.runes.length <= 32) {
      return cleaned;
    }
    final runes = cleaned.runes.toList();
    return '${String.fromCharCodes(runes.take(32))}…';
  }

  String _normalizedPreview(String value) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return '';
    }
    return lines.first
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }

  String _normalizedText(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ')
        .trim();
  }
}

class SessionDetail {
  SessionDetail({
    required this.summary,
    required this.turns,
  });

  final SessionSummary summary;
  final List<TurnDetail> turns;

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    return SessionDetail(
      summary: SessionSummary.fromJson(asMap(json['summary'])),
      turns: asList(json['turns'])
          .map((item) => TurnDetail.fromJson(asMap(item)))
          .toList(),
    );
  }
}

class TurnDetail {
  TurnDetail({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
    required this.error,
    required this.diff,
    required this.planExplanation,
    required this.plan,
    required this.items,
  });

  final String id;
  final String status;
  final int startedAt;
  final int completedAt;
  final int durationMs;
  final String error;
  final String diff;
  final String planExplanation;
  final List<PlanStep> plan;
  final List<TurnItem> items;

  factory TurnDetail.fromJson(Map<String, dynamic> json) {
    return TurnDetail(
      id: asString(json['id']),
      status: asString(json['status']),
      startedAt: asInt(json['startedAt']),
      completedAt: asInt(json['completedAt']),
      durationMs: asInt(json['durationMs']),
      error: asString(json['error']),
      diff: asString(json['diff']),
      planExplanation: asString(json['planExplanation']),
      plan: asList(json['plan'])
          .map((item) => PlanStep.fromJson(asMap(item)))
          .toList(),
      items: asList(json['items'])
          .map((item) => TurnItem.fromJson(asMap(item)))
          .toList(),
    );
  }
}

class PlanStep {
  PlanStep({
    required this.step,
    required this.status,
  });

  final String step;
  final String status;

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    return PlanStep(
      step: asString(json['step']),
      status: asString(json['status']),
    );
  }
}

class TurnItem {
  TurnItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.auxiliary,
    required this.metadata,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String status;
  final String auxiliary;
  final Map<String, String> metadata;

  factory TurnItem.fromJson(Map<String, dynamic> json) {
    return TurnItem(
      id: asString(json['id']),
      type: asString(json['type']),
      title: asString(json['title']),
      body: asString(json['body']),
      status: asString(json['status']),
      auxiliary: asString(json['auxiliary']),
      metadata: asMap(json['metadata'])
          .map((key, dynamic value) => MapEntry(key, asString(value))),
    );
  }
}

class PendingRequestView {
  PendingRequestView({
    required this.id,
    required this.method,
    required this.kind,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.reason,
    required this.summary,
    required this.choices,
    required this.createdAt,
    required this.params,
  });

  final String id;
  final String method;
  final String kind;
  final String threadId;
  final String turnId;
  final String itemId;
  final String reason;
  final String summary;
  final List<String> choices;
  final DateTime createdAt;
  final Map<String, dynamic> params;

  factory PendingRequestView.fromJson(Map<String, dynamic> json) {
    return PendingRequestView(
      id: asString(json['id']),
      method: asString(json['method']),
      kind: asString(json['kind']),
      threadId: asString(json['threadId']),
      turnId: asString(json['turnId']),
      itemId: asString(json['itemId']),
      reason: asString(json['reason']),
      summary: asString(json['summary']),
      choices: asList(json['choices']).map((item) => asString(item)).toList(),
      createdAt: parseDateTime(json['createdAt']),
      params: asMap(json['params']),
    );
  }
}

class ApprovalQuestion {
  ApprovalQuestion({
    required this.id,
    required this.question,
    required this.options,
  });

  final String id;
  final String question;
  final List<ApprovalQuestionOption> options;
}

class ApprovalQuestionOption {
  ApprovalQuestionOption({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

extension CodexStringHelpers on String {
  String headTailTruncated({
    required int maxLength,
    required int head,
    required int tail,
  }) {
    final trimmed = trim();
    final runes = trimmed.runes.toList();
    if (runes.length <= maxLength) {
      return trimmed;
    }

    final safeHead = math.min(head, runes.length);
    final safeTail = math.min(tail, math.max(0, runes.length - safeHead));
    if (safeHead <= 0 || safeTail <= 0 || safeHead + safeTail >= runes.length) {
      return trimmed;
    }

    final headText = String.fromCharCodes(runes.take(safeHead));
    final tailText = String.fromCharCodes(runes.skip(runes.length - safeTail));
    return '$headText … $tailText';
  }
}
