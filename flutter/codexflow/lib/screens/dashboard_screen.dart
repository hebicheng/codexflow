import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../state/app_model.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'approval_screen.dart';
import 'session_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final selectedAgentId = model.selectedStartAgentId;
    final filteredSessions = model.dashboard.sessions
        .where((session) => session.agentId == selectedAgentId)
        .toList();
    final allowedSessionIds = filteredSessions.map((item) => item.id).toSet();
    final filteredApprovals = model.dashboard.approvals
        .where((approval) => allowedSessionIds.contains(approval.threadId))
        .toList();
    final loadedCount =
        filteredSessions.where((session) => session.loaded).length;
    final activeCount = filteredSessions
        .where((session) => session.status == 'active' && !session.isEnded)
        .length;
    final pendingApprovalCount = filteredApprovals.length;

    final managedSessions = filteredSessions
        .where((session) => session.lifecycleStage == 'managed')
        .toList();
    final endedSessions =
        filteredSessions.where((session) => session.lifecycleStage == 'ended').toList();
    final runtimeSessions = filteredSessions
        .where(
          (session) => session.lifecycleStage == 'runtime_available',
        )
        .toList();
    final historySessions = filteredSessions
        .where(
          (session) => session.lifecycleStage == 'history_only',
        )
        .toList();

    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text('会话',
            style: roundedTextStyle(size: 17, weight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: PageScaffold(
        child: RefreshIndicator(
          color: Palette.accent,
          onRefresh: model.refreshDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: <Widget>[
              Row(
                children: <Widget>[
                  _AgentSwitchButton(model: model),
                  const Spacer(),
                  AgentStatusBadge(connected: model.isAgentOnline),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                childAspectRatio: 1.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  MetricCard(
                    title: '总会话',
                    value: '${filteredSessions.length}',
                    tone: Palette.softBlue,
                  ),
                  MetricCard(
                    title: '已加载',
                    value: '$loadedCount',
                    tone: Palette.accent,
                  ),
                  MetricCard(
                    title: '运行中',
                    value: '$activeCount',
                    tone: Palette.accent2,
                  ),
                  MetricCard(
                    title: '待审批',
                    value: '$pendingApprovalCount',
                    tone: Palette.warning,
                  ),
                ],
              ),
              if (model.operationNotice.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (model.operationNoticeIsError
                            ? Palette.danger
                            : Palette.success)
                        .appOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.operationNotice,
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: model.operationNoticeIsError
                          ? Palette.danger
                          : Palette.success,
                    ),
                  ),
                ),
              ],
              if (!model.isAgentOnline &&
                  model.agentConnectionError.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Palette.danger.appOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    model.agentConnectionError,
                    style: roundedTextStyle(
                        size: 12,
                        weight: FontWeight.w500,
                        color: Palette.danger),
                  ),
                ),
              ],
              if (pendingApprovalCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                const PanelCard(
                  compact: true,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.warning_rounded,
                          color: Palette.warning, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '当前有审批等待处理。',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Palette.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('列表',
                          style: roundedTextStyle(
                              size: 16, weight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(
                        '${filteredSessions.length}',
                        style: roundedTextStyle(
                            size: 12,
                            weight: FontWeight.w600,
                            color: Palette.mutedInk),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 84,
                    child: ActionButton(
                      title: '新建',
                      background: Palette.softBlue,
                      foreground: Colors.white,
                      icon: Icons.add,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (BuildContext context) =>
                              const NewSessionSheet(),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filteredSessions.isEmpty)
                const PanelCard(
                  compact: true,
                  child: Text(
                    '暂时没有会话。先确认 Agent 已连接，或者点上方“新建”。',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Palette.mutedInk,
                    ),
                  ),
                )
              else ...<Widget>[
                if (managedSessions.isNotEmpty)
                  _SessionGroup(
                    title: '已接管',
                    helper: '这些会话已经由 CodexFlow 后台托管，可以直接继续 steer、开始下一轮，或处理中断。',
                    sessions: managedSessions,
                  ),
                if (endedSessions.isNotEmpty)
                  _SessionGroup(
                    title: '已结束',
                    helper:
                        '这些会话的历史和 turns 仍然保留，但已经从 CodexFlow 托管态退出。需要继续时，再重新接管。',
                    sessions: endedSessions,
                  ),
                if (runtimeSessions.isNotEmpty)
                  _SessionGroup(
                    title: selectedAgentId == 'claude' ? '可接管 Runtime' : '待接管',
                    helper: selectedAgentId == 'claude'
                        ? '这些 Claude 会话当前在本机 runtime 中可见。接管后，CodexFlow 才能继续刷新状态、处理中断和后续操作。'
                        : '这些会话当前未接管，但运行时仍可继续接管。',
                    sessions: runtimeSessions,
                  ),
                if (historySessions.isNotEmpty)
                  _SessionGroup(
                    title: selectedAgentId == 'claude' ? '历史导入' : '历史会话',
                    helper: selectedAgentId == 'claude'
                        ? '这些 Claude 会话目前只发现了历史 transcript。可以查看历史，但不代表当前存在可接管 runtime。'
                        : '这些只是已发现的真实会话记录。先接管，才可以继续执行、处理中断和后续审批。',
                    sessions: historySessions,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentSwitchButton extends StatelessWidget {
  const _AgentSwitchButton({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    AgentOption? selected;
    for (final option in model.startAgentOptions) {
      if (option.id == model.selectedStartAgentId) {
        selected = option;
        break;
      }
    }
    final selectedName = selected?.name ?? 'Codex';

    return PopupMenuButton<String>(
      tooltip: '切换 Agent',
      onSelected: (String value) {
        model.setSelectedStartAgent(value);
      },
      itemBuilder: (BuildContext context) {
        return model.startAgentOptions.map((option) {
          final isSelected = option.id == model.selectedStartAgentId;
          return PopupMenuItem<String>(
            value: option.id,
            enabled: option.available,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    option.name,
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w600,
                      color: option.available ? Palette.ink : Palette.mutedInk,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_rounded, size: 16, color: Palette.softBlue),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.account_tree_rounded, size: 14, color: Palette.ink),
            const SizedBox(width: 6),
            Text(
              selectedName,
              style: roundedTextStyle(size: 12, weight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 14, color: Palette.ink),
          ],
        ),
      ),
    );
  }
}

class _SessionGroup extends StatelessWidget {
  const _SessionGroup({
    required this.title,
    required this.helper,
    required this.sessions,
  });

  final String title;
  final String helper;
  final List<SessionSummary> sessions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(title,
                  style: roundedTextStyle(size: 14, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(
                '${sessions.length}',
                style: roundedTextStyle(
                    size: 12, weight: FontWeight.w600, color: Palette.mutedInk),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            style: roundedTextStyle(
                size: 13,
                weight: FontWeight.w500,
                color: Palette.mutedInk,
                height: 1.45),
          ),
          const SizedBox(height: 10),
          ...sessions.map((session) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SessionRow(session: session),
              )),
        ],
      ),
    );
  }
}

class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.session,
  });

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final sessionApprovals = model.approvalsFor(session.id);
    final capabilities = model.capabilitiesForSession(session);
    final canPrimaryAction = (session.isEnded || !session.loaded)
        ? model.canResumeSession(session)
        : true;
    return PanelCard(
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => _openDetail(context),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            session.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: roundedTextStyle(
                                size: 16, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            session.cwd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: roundedTextStyle(
                              size: 12,
                              weight: FontWeight.w500,
                              color: Palette.mutedInk,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '更新 ${session.updatedAtDisplay}',
                            style: roundedTextStyle(
                                size: 11,
                                weight: FontWeight.w600,
                                color: Palette.mutedInk),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(
                      status: session.status,
                      waiting: session.hasWaitingState,
                      ended: session.isEnded,
                    ),
                  ],
                ),
                if (session.previewSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    session.previewSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: roundedTextStyle(
                        size: 13,
                        weight: FontWeight.w500,
                        color: Palette.mutedInk,
                        height: 1.45),
                  ),
                ],
                const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        CapsuleTag(
                          title: '托管',
                          value: session.loaded ? '已接管' : '未接管',
                        ),
                        if (session.isClaudeSession) ...<Widget>[
                          const SizedBox(width: 8),
                          CapsuleTag(
                            title: '链路',
                            value: session.runtimeAvailable ? 'Runtime' : 'History',
                          ),
                          if (session.loaded &&
                              session.runtimeAttachMode.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            CapsuleTag(
                              title: '接管',
                              value: session.runtimeAttachMode == 'resumed_existing'
                                  ? '现有 Runtime'
                                  : (session.runtimeAttachMode == 'opened_from_history'
                                      ? '历史新开'
                                      : '新建 Runtime'),
                            ),
                          ],
                        ],
                        const SizedBox(width: 8),
                        CapsuleTag(title: '来源', value: session.source),
                        const SizedBox(width: 8),
                        CapsuleTag(
                          title: '分支',
                          value:
                              session.branch.isEmpty ? '未识别' : session.branch),
                      if (session.lastTurnStatus.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        CapsuleTag(
                            title: '最近一轮',
                            value:
                                _lastTurnStatusLabel(session.lastTurnStatus)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _actionHint,
                  style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: _hintTone,
                      height: 1.45),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: Palette.line,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: ActionButton(
                  title: _primaryButtonTitle,
                  background: _primaryBackground,
                  foreground: _primaryForeground,
                  borderColor: _primaryBorder,
                  enabled: canPrimaryAction,
                  onPressed: () => _handlePrimaryAction(context),
                ),
              ),
            ],
          ),
          if (capabilities.supportsApprovals && session.pendingApprovals > 0) ...<Widget>[
            const SizedBox(height: 10),
            ActionButton(
              title: '快速处理审批 (${session.pendingApprovals})',
              background: Palette.warning.appOpacity(0.14),
              foreground: Palette.warning,
              borderColor: Palette.warning.appOpacity(0.22),
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SessionApprovalSheet(
                    title: session.displayName,
                    approvals: sessionApprovals,
                  ),
                );
              },
            ),
          ],
          if (capabilities.supportsArchive && (!session.loaded || session.isEnded)) ...<Widget>[
            const SizedBox(height: 10),
            ActionButton(
              title: session.isEnded ? '归档已结束会话' : '从列表移除',
              background: Colors.white,
              foreground: Palette.danger,
              borderColor: Palette.danger.appOpacity(0.20),
              onPressed: () async {
                await context.read<AppModel>().archiveSession(session);
              },
            ),
          ],
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(sessionId: session.id),
      ),
    );
  }

  Future<void> _handlePrimaryAction(BuildContext context) async {
    final model = context.read<AppModel>();
    if (session.isEnded || !session.loaded) {
      await model.resumeSession(session);
      return;
    }
    await model.endSession(session);
  }

  String get _primaryButtonTitle {
    if (session.isEnded) {
      return '重新接管';
    }
    if (!session.loaded) {
      if (session.isClaudeSession && !session.runtimeAvailable) {
        return '当前无 Runtime';
      }
      return '接管到 CodexFlow';
    }
    return session.lastTurnStatus == 'inProgress' ? '中断并结束' : '结束会话';
  }

  Color get _primaryBackground {
    if (session.isEnded || !session.loaded) {
      return Palette.softBlue;
    }
    return Palette.danger.appOpacity(0.12);
  }

  Color get _primaryForeground {
    if (session.isEnded || !session.loaded) {
      return Colors.white;
    }
    return Palette.danger;
  }

  Color get _primaryBorder {
    if (session.isEnded || !session.loaded) {
      return Colors.transparent;
    }
    return Palette.danger.appOpacity(0.20);
  }

  String get _actionHint {
    if (session.isEnded) {
      return '这个会话已经在 CodexFlow 中结束。历史和 turn 会保留；如需继续，重新接管即可。';
    }
    if (session.isClaudeSession && session.runtimeAvailable && !session.loaded) {
      return 'Claude runtime 当前可见，但还没接到 CodexFlow。接管后才能继续刷新状态、处理中断和下一轮。';
    }
    if (session.isClaudeSession &&
        session.historyAvailable &&
        !session.runtimeAvailable) {
      return '这是 Claude 历史导入会话。现在可以查看历史，但当前没有可接管 runtime。';
    }
    if (session.pendingApprovals > 0) {
      return '有 ${session.pendingApprovals} 个审批等待处理，先去审批页处理。';
    }
    if (!session.loaded && session.lastTurnStatus == 'inProgress') {
      return '这个会话还没被 CodexFlow 接管。先接管，之后才可以继续 steer 或中断。';
    }
    if (session.lastTurnStatus == 'inProgress') {
      return '点进去后可继续引导当前 turn，也可以中断。';
    }
    if (session.loaded) {
      return '点进去后可直接发送下一轮 prompt。';
    }
    return '这是历史会话。现在只能查看历史；接管后才可以开始下一轮。';
  }

  Color get _hintTone {
    if (session.isEnded) {
      return Palette.mutedInk;
    }
    if (session.pendingApprovals > 0) {
      return Palette.warning;
    }
    if (session.lastTurnStatus == 'inProgress') {
      return Palette.accent;
    }
    if (session.loaded) {
      return Palette.success;
    }
    return Palette.softBlue;
  }

  String _lastTurnStatusLabel(String status) {
    switch (status) {
      case 'inProgress':
        return '运行中';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }
}

class NewSessionSheet extends StatefulWidget {
  const NewSessionSheet({super.key});

  @override
  State<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<NewSessionSheet> {
  late final TextEditingController _cwdController;
  late final TextEditingController _promptController;
  bool _isCreating = false;
  String _submitError = '';

  @override
  void initState() {
    super.initState();
    _cwdController = TextEditingController();
    _promptController = TextEditingController();
  }

  @override
  void dispose() {
    _cwdController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge(<Listenable>[_cwdController, _promptController]),
      builder: (BuildContext context, Widget? child) {
        final trimmedCwd = _cwdController.text.trim();
        final trimmedPrompt = _promptController.text.trim();
        final canCreate = trimmedCwd.isNotEmpty && trimmedPrompt.isNotEmpty;

        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.7,
          maxChildSize: 0.96,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Palette.canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Palette.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Expanded(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text('新建会话',
                            style: roundedTextStyle(
                                size: 17, weight: FontWeight.w600)),
                        leading: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            '关闭',
                            style: roundedTextStyle(
                                size: 13,
                                weight: FontWeight.w600,
                                color: Palette.softBlue),
                          ),
                        ),
                      ),
                      body: PageScaffold(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                          children: <Widget>[
                            PanelCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Palette.softBlue
                                              .appOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '受控会话',
                                          style: roundedTextStyle(
                                            size: 11,
                                            weight: FontWeight.w700,
                                            color: Palette.softBlue,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '2 项必填',
                                        style: roundedTextStyle(
                                          size: 11,
                                          weight: FontWeight.w700,
                                          color: Palette.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '新建会话',
                                    style: roundedTextStyle(
                                        size: 26, weight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '填写目录和首条提示，CodexFlow 会立即建立一个可继续的会话。',
                                    style: roundedTextStyle(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: Palette.mutedInk,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      Text('工作目录',
                                          style: roundedTextStyle(
                                              size: 14,
                                              weight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(
                                        '绝对路径或 ~/repo',
                                        style: roundedTextStyle(
                                            size: 11,
                                            weight: FontWeight.w500,
                                            color: Palette.mutedInk),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  CodexTextField(
                                    controller: _cwdController,
                                    hintText:
                                        '/Users/hebicheng/workspace/aicoding-helper',
                                    monospaced: true,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      Text('首条提示',
                                          style: roundedTextStyle(
                                              size: 14,
                                              weight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(
                                        trimmedPrompt.isEmpty
                                            ? '未填写'
                                            : '${trimmedPrompt.length} 字',
                                        style: roundedTextStyle(
                                          size: 11,
                                          weight: FontWeight.w500,
                                          color: trimmedPrompt.isEmpty
                                              ? Palette.mutedInk
                                              : Palette.softBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  CodexTextField(
                                    controller: _promptController,
                                    hintText: '例如：继续实现剩余部分，并补上验证。',
                                    maxLines: 7,
                                    minLines: 7,
                                    autocapitalization:
                                        TextCapitalization.sentences,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: <Widget>[
                                      const Icon(Icons.auto_awesome,
                                          size: 14, color: Palette.softBlue),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '支持 `~/...` 路径，创建后会立即出现在会话列表。',
                                          style: roundedTextStyle(
                                              size: 12,
                                              weight: FontWeight.w500,
                                              color: Palette.mutedInk),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_submitError.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Palette.danger.appOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _submitError,
                                        style: roundedTextStyle(
                                            size: 13,
                                            weight: FontWeight.w500,
                                            color: Palette.danger),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  ActionButton(
                                    title: _isCreating ? '创建中…' : '创建会话',
                                    background: Palette.accent,
                                    foreground: Colors.white,
                                    fontSize: 14,
                                    icon: _isCreating ? null : Icons.add,
                                    enabled: canCreate && !_isCreating,
                                    onPressed: () async {
                                      if (!canCreate || _isCreating) {
                                        return;
                                      }
                                      final appModel = context.read<AppModel>();
                                      final navigator = Navigator.of(context);
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                        _isCreating = true;
                                        _submitError = '';
                                      });

                                      final success = await appModel.startSession(
                                        cwd: trimmedCwd,
                                        prompt: trimmedPrompt,
                                        agentId: appModel.selectedStartAgentId,
                                      );

                                      if (!mounted) {
                                        return;
                                      }

                                      if (success) {
                                        navigator.pop();
                                      } else {
                                        setState(() {
                                          _isCreating = false;
                                          final connectionError = appModel.connectionError;
                                          _submitError = connectionError.isEmpty
                                              ? '创建会话失败，请检查 Agent 状态和输入内容。'
                                              : connectionError;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
