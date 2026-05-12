import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import '../services/api_client.dart';

enum ApprovalActionType {
  choice,
  decision,
  submitText,
}

class ApprovalAction {
  ApprovalAction.choice(this.value) : type = ApprovalActionType.choice;

  ApprovalAction.decision(this.value) : type = ApprovalActionType.decision;

  ApprovalAction.submitText(this.value) : type = ApprovalActionType.submitText;

  final ApprovalActionType type;
  final Object? value;

  String get freeformText => value is String ? value as String : '';

  String get choiceValue {
    switch (type) {
      case ApprovalActionType.choice:
        return asString(value);
      case ApprovalActionType.decision:
        return value is String ? value as String : 'accept';
      case ApprovalActionType.submitText:
        return 'accept';
    }
  }

  Object? get decisionValue => value;
}

class AppModel extends ChangeNotifier {
  AppModel(this._prefs)
      : baseUrlString = _prefs.getString(_baseUrlKey) ?? '';

  static const _baseUrlKey = 'codexflow.baseURL';

  final SharedPreferences _prefs;

  String baseUrlString;
  DashboardResponse dashboard = DashboardResponse.placeholder();
  final Map<String, SessionDetail> sessionDetails = <String, SessionDetail>{};
  bool isRefreshing = false;
  bool isBootstrapped = false;
  bool isAgentOnline = false;
  String agentConnectionError = '';
  String connectionError = '';
  String operationNotice = '';
  bool operationNoticeIsError = false;
  String composerDraft = '';
  String selectedStartAgentId = 'codex';
  int _consecutiveDashboardFailures = 0;
  Timer? _noticeTimer;

  ApiClient _client() => ApiClient(baseUrlString: baseUrlString);

  Future<void> bootstrap() async {
    if (isBootstrapped) {
      return;
    }
    isBootstrapped = true;
    notifyListeners();
    await refreshDashboard();
  }

  void updateBaseUrlString(String value) {
    baseUrlString = value;
    notifyListeners();
  }

  Future<void> saveBaseUrl() async {
    await _prefs.setString(_baseUrlKey, baseUrlString);
  }

  Future<void> refreshDashboard() async {
    if (isRefreshing) {
      return;
    }
    isRefreshing = true;
    notifyListeners();

    try {
      final latestDashboard = await _client().dashboard();
      dashboard = latestDashboard;
      _syncSelectedAgent(latestDashboard);
      _consecutiveDashboardFailures = 0;
      isAgentOnline = latestDashboard.agent.connected;
      agentConnectionError = '';
    } catch (error) {
      _consecutiveDashboardFailures += 1;
      if (_consecutiveDashboardFailures >= 2 || !isAgentOnline) {
        isAgentOnline = false;
        agentConnectionError = error.toString();
      }
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  List<PendingRequestView> approvalsFor(String sessionId) {
    if (!supportsApprovalsForSessionId(sessionId)) {
      return <PendingRequestView>[];
    }
    final approvals = dashboard.approvals
        .where((item) => item.threadId == sessionId)
        .toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return approvals;
  }

  Future<void> loadSession(String id) async {
    try {
      final detail = await _client().sessionDetail(id);
      sessionDetails[id] = detail;
      connectionError = '';
      notifyListeners();
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<bool> startSession({
    required String cwd,
    required String prompt,
    required String agentId,
  }) async {
    try {
      final createdSession = await _client().startSession(
        cwd: cwd.trim(),
        prompt: prompt.trim(),
        agentId: agentId.trim().toLowerCase(),
      );
      _upsertSessionSummary(createdSession);
      connectionError = '';
      showNotice('会话已创建。');
      await refreshDashboard();
      await loadSession(createdSession.id);
      return true;
    } catch (error) {
      connectionError = error.toString();
      showNotice('创建会话失败：${error.toString()}', isError: true);
      notifyListeners();
      return false;
    }
  }

  Future<void> resumeSession(SessionSummary session) async {
    if (!canResumeSession(session)) {
      final message = session.resumeBlockedReason.isNotEmpty
          ? session.resumeBlockedReason
          : '这个会话当前不能重新接管。';
      connectionError = message;
      showNotice(message, isError: true);
      notifyListeners();
      return;
    }
    try {
      final updatedSession = await _client().resumeSession(session.id);
      _upsertSessionSummary(updatedSession);
      connectionError = '';
      showNotice(_resumeSuccessNotice(updatedSession));
      await refreshDashboard();
      await loadSession(session.id);
    } catch (error) {
      connectionError = error.toString();
      showNotice('接管失败：${error.toString()}', isError: true);
      notifyListeners();
    }
  }

  Future<void> archiveSession(SessionSummary session) async {
    try {
      await _client().archiveSession(session.id);
      sessionDetails.remove(session.id);
      await refreshDashboard();
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> endSession(SessionSummary session) async {
    try {
      await _client().endSession(session.id);
      await refreshDashboard();
      await loadSession(session.id);
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<bool> submitPrompt({
    required SessionSummary session,
    required String prompt,
    List<String> imageUploadIds = const <String>[],
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty && imageUploadIds.isEmpty) {
      return false;
    }

    try {
      if (session.lastTurnStatus == 'inProgress' &&
          session.lastTurnId.isNotEmpty) {
        await _client().steerTurn(
          sessionId: session.id,
          turnId: session.lastTurnId,
          prompt: trimmed,
          imageUploadIds: imageUploadIds,
        );
      } else {
        await _client().startTurn(
          sessionId: session.id,
          prompt: trimmed,
          imageUploadIds: imageUploadIds,
        );
      }
      await refreshDashboard();
      await loadSession(session.id);
      return true;
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<UploadedImageRef?> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final ref = await _client().uploadImage(bytes: bytes, fileName: fileName);
      return ref;
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> interrupt(SessionSummary session) async {
    if (session.lastTurnId.isEmpty) {
      return;
    }
    try {
      await _client().interruptTurn(
        sessionId: session.id,
        turnId: session.lastTurnId,
      );
      await refreshDashboard();
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> resolve({
    required PendingRequestView approval,
    required ApprovalAction action,
  }) async {
    try {
      await _client().resolveApproval(
        id: approval.id,
        result: _buildResult(approval, action),
      );
      await refreshDashboard();
      final session = dashboard.sessions.cast<SessionSummary?>().firstWhere(
            (item) => item?.id == approval.threadId,
            orElse: () => null,
          );
      if (session != null) {
        await loadSession(session.id);
      }
    } catch (error) {
      connectionError = error.toString();
      notifyListeners();
    }
  }

  Object? _buildResult(PendingRequestView approval, ApprovalAction action) {
    switch (approval.kind) {
      case 'command':
      case 'fileChange':
        return <String, dynamic>{'decision': action.decisionValue};
      case 'permissions':
        final choice = action.choiceValue;
        Object? permissions;
        switch (choice) {
          case 'session':
          case 'turn':
            permissions = approval.params['permissions'] ?? <String, dynamic>{};
            break;
          default:
            permissions = <String, dynamic>{
              'network': null,
              'fileSystem': null,
            };
        }

        Object? scope;
        switch (choice) {
          case 'session':
          case 'turn':
            scope = choice;
            break;
          default:
            scope = null;
        }

        return <String, dynamic>{
          'permissions': permissions,
          'scope': scope,
        };
      case 'userInput':
        final questionId = _firstQuestionId(approval.params) ?? 'reply';
        return <String, dynamic>{
          'answers': <String, dynamic>{
            questionId: <String, dynamic>{
              'answers': <String>[action.freeformText],
            },
          },
        };
      default:
        return <String, dynamic>{'decision': action.choiceValue};
    }
  }

  String? _firstQuestionId(Map<String, dynamic> params) {
    final questions = asList(params['questions']);
    for (final question in questions) {
      final object = asMap(question);
      final id = asString(object['id']);
      if (id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }

  void _upsertSessionSummary(SessionSummary session) {
    final sessions = <SessionSummary>[...dashboard.sessions];
    final existingIndex = sessions.indexWhere((item) => item.id == session.id);
    if (existingIndex >= 0) {
      sessions[existingIndex] = session;
    } else {
      sessions.add(session);
    }

    sessions.sort((left, right) {
      if (left.updatedAt == right.updatedAt) {
        return left.id.compareTo(right.id);
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });

    dashboard = DashboardResponse(
      agent: dashboard.agent,
      agents: dashboard.agents,
      defaultAgent: dashboard.defaultAgent,
      stats: dashboard.stats,
      sessions: sessions,
      approvals: dashboard.approvals,
    );
    notifyListeners();
  }

  List<AgentOption> get startAgentOptions => dashboard.agents;

  AgentOption? get selectedAgentOption {
    for (final option in dashboard.agents) {
      if (option.id == selectedStartAgentId) {
        return option;
      }
    }
    return null;
  }

  List<PendingRequestView> get selectedAgentApprovals {
    final allowedSessionIds = dashboard.sessions
        .where((session) => session.agentId == selectedStartAgentId)
        .map((session) => session.id)
        .toSet();
    return dashboard.approvals
        .where((approval) => allowedSessionIds.contains(approval.threadId))
        .toList();
  }

  AgentCapabilities capabilitiesForSession(SessionSummary session) {
    for (final option in dashboard.agents) {
      if (option.id == session.agentId) {
        return option.capabilities;
      }
    }
    return AgentCapabilities(
      supportsInterruptTurn: true,
      supportsApprovals: true,
      supportsArchive: true,
      supportsResume: true,
      supportsHistoryImport: false,
    );
  }

  bool canResumeSession(SessionSummary session) {
    return capabilitiesForSession(session).supportsResume && session.canResume;
  }

  String _resumeSuccessNotice(SessionSummary session) {
    if (!session.isClaudeSession) {
      return '会话已接管，可继续发消息。';
    }
    switch (session.runtimeAttachMode) {
      case 'resumed_existing':
        return '已接入现有 Claude runtime。';
      case 'opened_from_history':
        return '已为这条 Claude 历史会话打开新的 runtime。';
      case 'new_session':
        return '已打开新的 Claude runtime。';
      default:
        return 'Claude 会话已接管。';
    }
  }

  void showNotice(String message, {bool isError = false}) {
    _noticeTimer?.cancel();
    operationNotice = message;
    operationNoticeIsError = isError;
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      operationNotice = '';
      operationNoticeIsError = false;
      notifyListeners();
    });
  }

  bool supportsApprovalsForSessionId(String sessionId) {
    SessionSummary? target;
    for (final session in dashboard.sessions) {
      if (session.id == sessionId) {
        target = session;
        break;
      }
    }
    if (target == null) {
      return true;
    }
    return capabilitiesForSession(target).supportsApprovals;
  }

  void setSelectedStartAgent(String id) {
    final normalized = id.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final exists = dashboard.agents
        .any((item) => item.id == normalized && item.available);
    if (!exists) {
      return;
    }
    selectedStartAgentId = normalized;
    notifyListeners();
  }

  void _syncSelectedAgent(DashboardResponse latestDashboard) {
    final availableIds = latestDashboard.agents
        .where((item) => item.available)
        .map((item) => item.id)
        .toSet();

    if (availableIds.contains(selectedStartAgentId)) {
      return;
    }

    final normalizedDefault = latestDashboard.defaultAgent.trim().toLowerCase();
    if (availableIds.contains(normalizedDefault)) {
      selectedStartAgentId = normalizedDefault;
      return;
    }

    selectedStartAgentId = availableIds.contains('codex')
        ? 'codex'
        : (availableIds.isNotEmpty ? availableIds.first : 'codex');
  }
}
