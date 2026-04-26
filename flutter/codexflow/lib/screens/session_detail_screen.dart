import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../state/app_model.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'approval_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late final TextEditingController _promptController;
  Timer? _timer;
  int _tick = 0;
  bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<_ComposerAttachment> _attachments = <_ComposerAttachment>[];

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshSessionPage());
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollIfNeeded(),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  SessionDetail? _detail(AppModel model) =>
      model.sessionDetails[widget.sessionId];

  SessionSummary? _summary(AppModel model) {
    final detail = _detail(model);
    if (detail != null) {
      return detail.summary;
    }
    return model.dashboard.sessions.cast<SessionSummary?>().firstWhere(
      (session) => session?.id == widget.sessionId,
      orElse: () => null,
    );
  }

  List<PendingRequestView> _sessionApprovals(AppModel model) =>
      model.approvalsFor(widget.sessionId);

  Future<void> _pollIfNeeded() async {
    if (!mounted) {
      return;
    }
    final model = context.read<AppModel>();
    final summary = _summary(model);
    final approvals = _sessionApprovals(model);
    if (summary == null) {
      await _refreshSessionPage();
      return;
    }
    if (summary.isEnded) {
      return;
    }
    if (approvals.isNotEmpty ||
        summary.hasWaitingState ||
        summary.lastTurnStatus == 'inProgress') {
      await _refreshSessionPage();
      return;
    }
    if (summary.loaded) {
      _tick += 1;
      if (_tick % 2 == 0) {
        await _refreshSessionPage();
      }
    }
  }

  Future<void> _refreshSessionPage() async {
    final model = context.read<AppModel>();
    await model.refreshDashboard();
    await model.loadSession(widget.sessionId);
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploadingImage) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _isUploadingImage = true;
    });
    try {
      final model = context.read<AppModel>();
      final uploaded = await model.uploadImage(
        bytes: bytes,
        fileName: image.name.isEmpty ? 'attachment.jpg' : image.name,
      );
      if (!mounted || uploaded == null) {
        return;
      }
      setState(() {
        _attachments.add(
          _ComposerAttachment(
            id: '${DateTime.now().microsecondsSinceEpoch}-${uploaded.id}',
            uploadId: uploaded.id,
            name: uploaded.name,
            bytes: bytes,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final detail = _detail(model);
    final summary = _summary(model);
    final capabilities = summary == null
        ? AgentCapabilities(
            supportsInterruptTurn: true,
            supportsApprovals: true,
            supportsArchive: true,
            supportsResume: true,
            supportsHistoryImport: false,
          )
        : model.capabilitiesForSession(summary);
    final supportsApprovals = capabilities.supportsApprovals;
    final supportsInterruptTurn = capabilities.supportsInterruptTurn;
    final supportsResume =
        summary == null ? capabilities.supportsResume : model.canResumeSession(summary);
    final orderedTurns = detail == null
        ? const <TurnDetail>[]
        : detail.turns.reversed.toList();
    final activeTurn = orderedTurns.cast<TurnDetail?>().firstWhere(
      (turn) => turn?.status == 'inProgress',
      orElse: () => null,
    );
    final recentTurns = orderedTurns
        .where((turn) => turn.id != activeTurn?.id)
        .toList();
    final sessionApprovals =
        supportsApprovals ? _sessionApprovals(model) : <PendingRequestView>[];
    final activeTurnApprovals = activeTurn == null
        ? const <PendingRequestView>[]
        : sessionApprovals
              .where((approval) => approval.turnId == activeTurn.id)
              .toList();
    final remainingSessionApprovals = activeTurn == null
        ? sessionApprovals
        : sessionApprovals
              .where((approval) => approval.turnId != activeTurn.id)
              .toList();

    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text(
          summary?.displayName ?? '会话详情',
          style: roundedTextStyle(size: 17, weight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: PageScaffold(
        child: RefreshIndicator(
          color: Palette.accent,
          onRefresh: _refreshSessionPage,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: <Widget>[
              if (model.operationNotice.isNotEmpty) ...<Widget>[
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
                const SizedBox(height: 12),
              ],
              if (summary != null) ...<Widget>[
                _SummaryCard(
                  summary: summary,
                  supportsApprovals: supportsApprovals,
                ),
                const SizedBox(height: 12),
                if (supportsApprovals && remainingSessionApprovals.isNotEmpty) ...<Widget>[
                  PanelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              '当前会话待审批',
                              style: roundedTextStyle(
                                size: 16,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${remainingSessionApprovals.length}',
                              style: roundedTextStyle(
                                size: 12,
                                weight: FontWeight.w600,
                                color: Palette.mutedInk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ApprovalList(
                          approvals: remainingSessionApprovals,
                          showSessionLabel: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (summary.isEnded || !summary.loaded)
                  _TakeoverCard(
                    summary: summary,
                    supportsResume: supportsResume,
                    onPressed: () async {
                      await model.resumeSession(summary);
                      await _refreshSessionPage();
                    },
                  )
                else
                  _ComposerCard(
                    summary: summary,
                    promptController: _promptController,
                    attachments: _attachments,
                    isUploadingImage: _isUploadingImage,
                    onPickImage: _pickAndUploadImage,
                    onRemoveAttachment: (String id) {
                      setState(() {
                        _attachments.removeWhere((item) => item.id == id);
                      });
                    },
                    onSubmit: () async {
                      final sent = await model.submitPrompt(
                        session: summary,
                        prompt: _promptController.text.trim(),
                        imageUploadIds: _attachments
                            .map((item) => item.uploadId)
                            .toList(),
                      );
                      if (sent) {
                        _promptController.clear();
                        setState(() {
                          _attachments.clear();
                        });
                      }
                    },
                    supportsInterruptTurn: supportsInterruptTurn,
                    onInterrupt: summary.lastTurnStatus == 'inProgress'
                            && supportsInterruptTurn
                        ? () async {
                            await model.interrupt(summary);
                          }
                        : null,
                    onEnd: () async {
                      await model.endSession(summary);
                      await _refreshSessionPage();
                    },
                  ),
                const SizedBox(height: 12),
              ],
              if (detail != null) ...<Widget>[
                if (detail.turns.isEmpty)
                  PanelCard(
                    compact: true,
                    child: Text(
                      _emptyStateMessage(summary),
                      style: roundedTextStyle(
                        size: 13,
                        weight: FontWeight.w500,
                        color: Palette.mutedInk,
                      ),
                    ),
                  )
                else ...<Widget>[
                  if (activeTurn != null) ...<Widget>[
                    Text(
                      '当前运行中',
                      style: roundedTextStyle(
                        size: 16,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ActiveTurnCard(
                      turn: activeTurn,
                      approvals: activeTurnApprovals,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (recentTurns.isNotEmpty) ...<Widget>[
                    Text(
                      '最近的 turn',
                      style: roundedTextStyle(
                        size: 16,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...recentTurns.map(
                      (turn) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TurnCard(turn: turn),
                      ),
                    ),
                  ],
                ],
              ] else
                PanelCard(
                  compact: true,
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Palette.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '正在加载会话详情…',
                        style: roundedTextStyle(
                          size: 13,
                          weight: FontWeight.w500,
                          color: Palette.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _emptyStateMessage(SessionSummary? summary) {
    if (summary != null && summary.isEnded) {
      return '这个会话已经结束。当前没有更多 turn 可展示；如果要继续执行，先重新接管。';
    }
    if (summary?.loaded == true) {
      return '这个会话还没有 turn。你可以直接在上面输入，开始第一轮。';
    }
    return '这个会话当前没有可展示的 turn 历史。先接管后，才能继续在 CodexFlow 里执行。';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.supportsApprovals,
  });

  final SessionSummary summary;
  final bool supportsApprovals;

  @override
  Widget build(BuildContext context) {
    final stateTone = summary.isEnded
        ? Palette.mutedInk
        : ((supportsApprovals && summary.pendingApprovals > 0)
              ? Palette.warning
              : (summary.loaded ? Palette.success : Palette.softBlue));

    return PanelCard(
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
                      summary.displayName,
                      style: roundedTextStyle(
                        size: 16,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary.cwd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: roundedTextStyle(
                        size: 12,
                        weight: FontWeight.w500,
                        color: Palette.mutedInk,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusPill(
                status: summary.status,
                waiting: summary.hasWaitingState,
                ended: summary.isEnded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                CapsuleTag(
                  title: '托管',
                  value: summary.loaded ? '已接管' : '未接管',
                ),
                if (summary.isClaudeSession) ...<Widget>[
                  const SizedBox(width: 8),
                  CapsuleTag(
                    title: '链路',
                    value: summary.runtimeAvailable ? 'Runtime' : 'History',
                  ),
                  if (summary.loaded && summary.runtimeAttachMode.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    CapsuleTag(
                      title: '接管',
                      value: summary.runtimeAttachMode == 'resumed_existing'
                          ? '现有 Runtime'
                          : (summary.runtimeAttachMode == 'opened_from_history'
                              ? '历史新开'
                              : '新建 Runtime'),
                    ),
                  ],
                ],
                const SizedBox(width: 8),
                CapsuleTag(title: '来源', value: summary.source),
                const SizedBox(width: 8),
                CapsuleTag(
                  title: '分支',
                  value: summary.branch.isEmpty ? '未识别' : summary.branch,
                ),
                const SizedBox(width: 8),
                CapsuleTag(title: '模型', value: summary.modelProvider),
              ],
            ),
          ),
          if (summary.previewSummary.isNotEmpty &&
              summary.previewSummary != summary.displayName) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '首条消息',
              style: roundedTextStyle(
                size: 12,
                weight: FontWeight.w600,
                color: Palette.mutedInk,
              ),
            ),
            const SizedBox(height: 4),
            HeadTailExcerptBlock(
              raw: summary.preview,
              head: 170,
              tail: 110,
              style: roundedTextStyle(
                size: 13,
                weight: FontWeight.w500,
                color: Palette.mutedInk,
                height: 1.45,
              ),
            ),
          ],
          if (supportsApprovals && summary.pendingApprovals > 0) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '这个会话当前有 ${summary.pendingApprovals} 个审批等待处理，你可以直接在下面处理，也可以去“审批”页集中处理。',
              style: roundedTextStyle(
                size: 13,
                weight: FontWeight.w500,
                color: Palette.warning,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: stateTone.appOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 4,
                  height: 56,
                  decoration: BoxDecoration(
                    color: stateTone,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _actionSummary(summary),
                    style: roundedTextStyle(
                      size: 13,
                      weight: FontWeight.w500,
                      color: stateTone,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionSummary(SessionSummary summary) {
    if (summary.isEnded) {
      return '这个会话已经在 CodexFlow 中结束。历史和 turn 会保留，但不再由 CodexFlow 托管；如需继续，请重新接管。';
    }
    if (summary.isClaudeSession &&
        summary.loaded &&
        summary.runtimeAttachMode == 'resumed_existing') {
      return '当前这条 Claude 会话已经重新接入现有 runtime。你现在看到的是原 runtime 的继续态，可以直接开始下一轮或继续处理中断。';
    }
    if (summary.isClaudeSession &&
        summary.loaded &&
        summary.runtimeAttachMode == 'opened_from_history') {
      return '当前这条 Claude 会话由 CodexFlow 新开 runtime 托管。历史 transcript 会继续保留显示，但后续运行状态来自这条新 runtime。';
    }
    if (summary.isClaudeSession &&
        summary.loaded &&
        summary.runtimeAttachMode == 'new_session') {
      return '这是由 CodexFlow 新建的 Claude 会话。当前 runtime 和历史从一开始就是同一条链路。';
    }
    if (!summary.loaded && summary.lastTurnStatus == 'inProgress') {
      return '这个会话当前还没被 CodexFlow 接管。现在只能查看历史；点下面“Resume 并接管会话”后，才可以继续 steer、处理中断和刷新运行状态。';
    }
    if (summary.lastTurnStatus == 'inProgress') {
      return '当前有一轮正在运行。这个页面会自动刷新最近 turn 的内容；你也可以继续 steer 或中断。';
    }
    if (summary.loaded) {
      return '当前没有运行中的 turn。你可以直接输入新的 prompt，开始下一轮。';
    }
    return '这个会话当前未接管。你可以查看历史；如果需要继续执行，先接管到 CodexFlow 后台。';
  }
}

class _TakeoverCard extends StatelessWidget {
  const _TakeoverCard({
    required this.summary,
    required this.supportsResume,
    required this.onPressed,
  });

  final SessionSummary summary;
  final bool supportsResume;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.refresh, size: 14, color: Palette.softBlue),
              const SizedBox(width: 8),
              Text(
                summary.isEnded ? '会话已结束' : '先接管，再继续',
                style: roundedTextStyle(size: 16, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _takeoverSummary(summary),
            style: roundedTextStyle(
              size: 13,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ActionButton(
            title: (!summary.isEnded &&
                    summary.isClaudeSession &&
                    !summary.runtimeAvailable)
                ? '当前无 Runtime'
                : (summary.isEnded ? '重新接管会话' : 'Resume 并接管会话'),
            background:
                supportsResume ? Palette.softBlue : Palette.mutedInk.appOpacity(0.35),
            foreground: Colors.white,
            fontSize: 14,
            enabled: supportsResume,
            onPressed: () async => onPressed(),
          ),
        ],
      ),
    );
  }

  String _takeoverSummary(SessionSummary summary) {
    if (summary.isEnded) {
      return '这个会话已经在 CodexFlow 中结束了。历史记录仍然可看；如果你想继续发 prompt 或重新托管审批/状态刷新，先重新接管。';
    }
    if (summary.isClaudeSession &&
        summary.runtimeAvailable &&
        !summary.loaded) {
      return '已经检测到 Claude live runtime。接入后，这个页面才会开始跟踪运行状态、处理中断，并允许继续下一轮。';
    }
    if (summary.isClaudeSession &&
        summary.historyAvailable &&
        !summary.runtimeAvailable) {
      return '这是 Claude 历史导入记录。当前可以查看历史，但本机没有发现对应 live runtime。';
    }
    if (!summary.canResume && summary.resumeBlockedReason.isNotEmpty) {
      return summary.resumeBlockedReason;
    }
    if (summary.lastTurnStatus == 'inProgress') {
      return '这个会话可能仍在别处运行，但当前不在 CodexFlow 里托管。先接管后，CodexFlow 才能继续刷新状态、处理审批，并允许你继续 steer 或中断。';
    }
    return '这个会话现在只是历史记录，还没有被 CodexFlow 接管。接管后，这个页面才会出现“开始下一轮”或“继续引导当前 turn”的操作。';
  }
}

class _ComposerAttachment {
  _ComposerAttachment({
    required this.id,
    required this.uploadId,
    required this.name,
    required this.bytes,
  });

  final String id;
  final String uploadId;
  final String name;
  final Uint8List bytes;
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.summary,
    required this.promptController,
    required this.attachments,
    required this.isUploadingImage,
    required this.onPickImage,
    required this.onRemoveAttachment,
    required this.onSubmit,
    required this.supportsInterruptTurn,
    required this.onInterrupt,
    required this.onEnd,
  });

  final SessionSummary summary;
  final TextEditingController promptController;
  final List<_ComposerAttachment> attachments;
  final bool isUploadingImage;
  final Future<void> Function() onPickImage;
  final void Function(String id) onRemoveAttachment;
  final Future<void> Function() onSubmit;
  final bool supportsInterruptTurn;
  final Future<void> Function()? onInterrupt;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final isSteering = summary.lastTurnStatus == 'inProgress';
    final accentTone = isSteering ? Palette.accent2 : Palette.accent;
    return ListenableBuilder(
      listenable: promptController,
      builder: (BuildContext context, Widget? child) {
        final trimmedPrompt = promptController.text.trim();
        final canSubmit = trimmedPrompt.isNotEmpty || attachments.isNotEmpty;
        return PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    isSteering ? '继续当前 turn' : '开始下一轮',
                    style: roundedTextStyle(size: 16, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    isSteering ? 'steer' : 'new turn',
                    style: roundedTextStyle(
                      size: 11,
                      weight: FontWeight.w700,
                      color: accentTone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isSteering ? '补充调整方向或新增约束。' : '输入新的 prompt，继续这个会话。',
                style: roundedTextStyle(
                  size: 13,
                  weight: FontWeight.w500,
                  color: Palette.mutedInk,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Opacity(
                    opacity: isUploadingImage ? 0.45 : 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: isUploadingImage ? null : onPickImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Palette.shell,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Palette.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.photo,
                              size: 14,
                              color: Palette.ink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isUploadingImage ? '上传中…' : '添加图片',
                              style: roundedTextStyle(
                                size: 12,
                                weight: FontWeight.w600,
                                color: Palette.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (attachments.isNotEmpty)
                    Text(
                      '已选 ${attachments.length} 张',
                      style: roundedTextStyle(
                        size: 12,
                        weight: FontWeight.w600,
                        color: Palette.mutedInk,
                      ),
                    ),
                ],
              ),
              if (attachments.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: attachments
                        .map(
                          (attachment) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    attachment.bytes,
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: InkWell(
                                    onTap: () =>
                                        onRemoveAttachment(attachment.id),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Icon(
                                      Icons.cancel,
                                      size: 20,
                                      color: Palette.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CodexTextField(
                controller: promptController,
                hintText: isSteering
                    ? '例如：先别改接口，优先把测试补齐。'
                    : '例如：继续实现剩余部分，并补上验证。',
                maxLines: 6,
                minLines: 6,
                autocapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              ActionButton(
                title: isSteering ? '发送 steer' : '开始这一轮',
                background: accentTone,
                foreground: Colors.white,
                icon: isSteering ? Icons.alt_route : Icons.auto_awesome,
                fontSize: 14,
                enabled: canSubmit && !isUploadingImage,
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await onSubmit();
                },
              ),
              const SizedBox(height: 10),
              if (isSteering)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ActionButton(
                        title: '先中断本轮',
                        background: Palette.warning.appOpacity(0.12),
                        foreground: Palette.warning,
                        borderColor: Palette.warning.appOpacity(0.18),
                        icon: Icons.pause,
                        fontSize: 14,
                        onPressed: onInterrupt == null
                            ? null
                            : () async {
                                FocusScope.of(context).unfocus();
                                await onInterrupt!();
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionButton(
                        title: '中断并结束',
                        background: Palette.danger.appOpacity(0.12),
                        foreground: Palette.danger,
                        borderColor: Palette.danger.appOpacity(0.18),
                        icon: Icons.stop,
                        fontSize: 14,
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          await onEnd();
                        },
                      ),
                    ),
                  ],
                )
              else
                ActionButton(
                  title: '结束这个会话',
                  background: Palette.danger.appOpacity(0.10),
                  foreground: Palette.danger,
                  borderColor: Palette.danger.appOpacity(0.16),
                  icon: Icons.stop_circle_outlined,
                  fontSize: 14,
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    await onEnd();
                  },
                  ),
              if (isSteering && !supportsInterruptTurn) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '当前 Agent 不支持本轮中断，将等待本轮自然结束。',
                  style: roundedTextStyle(
                    size: 12,
                    weight: FontWeight.w500,
                    color: Palette.mutedInk,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class TurnCard extends StatelessWidget {
  const TurnCard({super.key, required this.turn, this.isLive = false});

  final TurnDetail turn;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: isLive
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Palette.warning.appOpacity(0.35),
                width: 1.5,
              ),
            )
          : null,
      child: PanelCard(
        compact: true,
        child: TurnCardBody(turn: turn, isLive: isLive),
      ),
    );
  }
}

class ActiveTurnCard extends StatelessWidget {
  const ActiveTurnCard({
    super.key,
    required this.turn,
    required this.approvals,
  });

  final TurnDetail turn;
  final List<PendingRequestView> approvals;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.warning.appOpacity(0.35), width: 1.5),
      ),
      child: PanelCard(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (approvals.isNotEmpty) ...<Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.warning_rounded,
                    color: Palette.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前 turn 待审批',
                    style: roundedTextStyle(
                      size: 14,
                      weight: FontWeight.w600,
                      color: Palette.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${approvals.length}',
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Palette.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...approvals.map(
                (approval) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ApprovalCardBody(
                    approval: approval,
                    showSessionLabel: false,
                    embedded: true,
                  ),
                ),
              ),
              Container(height: 1, color: Palette.line),
              const SizedBox(height: 12),
            ],
            TurnCardBody(turn: turn, isLive: true),
          ],
        ),
      ),
    );
  }
}

class TurnCardBody extends StatelessWidget {
  const TurnCardBody({super.key, required this.turn, required this.isLive});

  final TurnDetail turn;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final firstUserItem = turn.items.cast<TurnItem?>().firstWhere(
      (item) => item?.type == 'userMessage' && item!.body.trim().isNotEmpty,
      orElse: () => null,
    );
    final lastAgentItem = turn.items.reversed.cast<TurnItem?>().firstWhere(
      (item) => item?.type == 'agentMessage' && item!.body.trim().isNotEmpty,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        _turnStatusLabel(turn.status),
                        style: roundedTextStyle(
                          size: 14,
                          weight: FontWeight.w600,
                          color: _statusTone(turn.status),
                        ),
                      ),
                      if (isLive) ...<Widget>[
                        const SizedBox(width: 6),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.sensors,
                              size: 12,
                              color: Palette.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '实时更新',
                              style: roundedTextStyle(
                                size: 11,
                                weight: FontWeight.w600,
                                color: Palette.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    turn.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: roundedTextStyle(
                      size: 11,
                      weight: FontWeight.w500,
                      color: Palette.mutedInk,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (turn.durationMs > 0)
              Text(
                '${turn.durationMs ~/ 1000}s',
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w600,
                  color: Palette.mutedInk,
                ),
              ),
          ],
        ),
        if (turn.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            turn.error,
            style: roundedTextStyle(
              size: 13,
              weight: FontWeight.w500,
              color: Palette.danger,
            ),
          ),
        ],
        if (firstUserItem != null || lastAgentItem != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '本轮摘要',
            style: roundedTextStyle(size: 12, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (firstUserItem != null) ...<Widget>[
            ExcerptSummaryCard(
              title: '用户提示',
              icon: Icons.person_outline,
              tone: Palette.softBlue,
              raw: firstUserItem.body,
              head: 170,
              tail: 110,
            ),
            const SizedBox(height: 8),
          ],
          if (lastAgentItem != null)
            ExcerptSummaryCard(
              title: 'Agent 输出',
              icon: Icons.auto_awesome,
              tone: Palette.accent,
              raw: lastAgentItem.body,
              head: 210,
              tail: 140,
            ),
        ],
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              if (turn.plan.isNotEmpty) ...<Widget>[
                CapsuleTag(title: '计划', value: '${turn.plan.length} 步'),
                const SizedBox(width: 8),
              ],
              if (turn.diff.isNotEmpty) ...<Widget>[
                const CapsuleTag(title: 'Diff', value: '可查看'),
                const SizedBox(width: 8),
              ],
              if (turn.items.isNotEmpty)
                CapsuleTag(title: '时间线', value: '${turn.items.length} 项'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ActionButton(
          title: '查看详情',
          background: Palette.shell,
          foreground: Palette.ink,
          fontSize: 14,
          onPressed: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => TurnDetailSheet(turn: turn),
            );
          },
        ),
      ],
    );
  }

  String _turnStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'inProgress':
        return '运行中';
      default:
        return status;
    }
  }

  Color _statusTone(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'failed':
        return Palette.danger;
      case 'inProgress':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }
}

class ExcerptSummaryCard extends StatelessWidget {
  const ExcerptSummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.raw,
    required this.head,
    required this.tail,
  });

  final String title;
  final IconData icon;
  final Color tone;
  final String raw;
  final int head;
  final int tail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.appOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.appOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 12, color: tone),
              const SizedBox(width: 6),
              Text(
                title,
                style: roundedTextStyle(
                  size: 11,
                  weight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          HeadTailExcerptBlock(
            raw: _normalizeExcerptText(raw),
            head: head,
            tail: tail,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.ink,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeExcerptText(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return '';
  }

  // Keep visible meaning but remove Markdown syntax noise for card excerpts.
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'^```[^\n]*\n?([\s\S]*?)\n?```$', multiLine: true),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(RegExp(r'```[\s\S]*?```'), (match) {
    final block = match.group(0) ?? '';
    return block
        .replaceAll(RegExp(r'^```[^\n]*\n?'), '')
        .replaceAll(RegExp(r'\n?```$'), '');
  });
  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(
    RegExp(r'^\s{0,3}(#{1,6}\s+|>\s+|[-*+]\s+|\d+\.\s+)', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'^\s*([-*_]\s*){3,}$', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\\([\\`*_{}\[\]()#+\-.!|>~])'), r'$1');

  // Repeatedly strip paired inline markers so nested combinations are handled.
  for (var i = 0; i < 4; i++) {
    final before = text;
    text = text.replaceAllMapped(
      RegExp(r'\*\*\*([^*\n]+)\*\*\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'___([^_\n]+)___'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*\*([^*\n]+)\*\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'__([^_\n]+)__'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'~~([^~\n]+)~~'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*([^*\n]+)\*'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'_([^_\n]+)_'),
      (match) => match.group(1) ?? '',
    );
    if (text == before) {
      break;
    }
  }

  text = text.replaceAll(RegExp(r'(^|\s)[*_~]+'), ' ');
  text = text.replaceAll(RegExp(r'[*_~]+(?=\s|$)'), '');
  text = text.replaceAll('|', ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  return text;
}

class TurnDetailSheet extends StatefulWidget {
  const TurnDetailSheet({super.key, required this.turn});

  final TurnDetail turn;

  @override
  State<TurnDetailSheet> createState() => _TurnDetailSheetState();
}

class _TurnDetailSheetState extends State<TurnDetailSheet> {
  bool showPlan = true;
  bool showDiff = false;
  bool showTimeline = false;

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.7,
      maxChildSize: 0.97,
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
                    title: Text(
                      'Turn 详情',
                      style: roundedTextStyle(
                        size: 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                    centerTitle: true,
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          '关闭',
                          style: roundedTextStyle(
                            size: 13,
                            weight: FontWeight.w600,
                            color: Palette.softBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  body: PageScaffold(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: <Widget>[
                        PanelCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Text(
                                    _turnStatusLabel(turn.status),
                                    style: roundedTextStyle(
                                      size: 16,
                                      weight: FontWeight.w600,
                                      color: _statusTone(turn.status),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (turn.durationMs > 0)
                                    Text(
                                      '${turn.durationMs ~/ 1000}s',
                                      style: roundedTextStyle(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: Palette.mutedInk,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                turn.id,
                                style: roundedTextStyle(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: Palette.mutedInk,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (turn.planExplanation.isNotEmpty ||
                            turn.plan.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: '计划',
                            isExpanded: showPlan,
                            onToggle: () =>
                                setState(() => showPlan = !showPlan),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (turn
                                    .planExplanation
                                    .isNotEmpty) ...<Widget>[
                                  Text(
                                    turn.planExplanation,
                                    style: roundedTextStyle(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: Palette.mutedInk,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                ...turn.plan.map(
                                  (step) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(top: 5),
                                          decoration: BoxDecoration(
                                            color: _stepColor(step.status),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${step.step} · ${_stepStatusLabel(step.status)}',
                                            style: roundedTextStyle(
                                              size: 12,
                                              weight: FontWeight.w500,
                                              color: Palette.mutedInk,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (turn.diff.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: 'Diff',
                            isExpanded: showDiff,
                            onToggle: () =>
                                setState(() => showDiff = !showDiff),
                            child: DiffBlock(diff: turn.diff),
                          ),
                        ],
                        if (turn.items.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          DisclosureSection(
                            title: '时间线',
                            isExpanded: showTimeline,
                            onToggle: () =>
                                setState(() => showTimeline = !showTimeline),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: turn.items
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TimelineEntryView(item: item),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
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
  }

  String _turnStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'inProgress':
        return '运行中';
      default:
        return status;
    }
  }

  Color _statusTone(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'failed':
        return Palette.danger;
      case 'inProgress':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }

  Color _stepColor(String status) {
    switch (status) {
      case 'completed':
        return Palette.success;
      case 'in_progress':
        return Palette.warning;
      default:
        return Palette.line;
    }
  }

  String _stepStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'in_progress':
        return '进行中';
      default:
        return '待处理';
    }
  }
}

class DisclosureSection extends StatelessWidget {
  const DisclosureSection({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      compact: true,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: <Widget>[
                Text(
                  title,
                  style: roundedTextStyle(size: 12, weight: FontWeight.w600),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Palette.ink,
                ),
              ],
            ),
          ),
          if (isExpanded) ...<Widget>[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class TimelineEntryView extends StatelessWidget {
  const TimelineEntryView({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final bodyPreview = normalizedDisplayText(
      item.body,
    ).headTailTruncated(maxLength: 220, head: 140, tail: 72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.appOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TimelineTypeTag(item: item),
              const Spacer(),
              if (item.status.isNotEmpty)
                Text(
                  item.status,
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: Palette.mutedInk,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (item.type == 'userMessage')
            HeadTailExcerptBlock(
              raw: item.body,
              head: 170,
              tail: 110,
              style: roundedTextStyle(
                size: 12,
                weight: FontWeight.w500,
                color: Palette.mutedInk,
                height: 1.45,
              ),
            )
          else if (item.type == 'agentMessage')
            MarkdownBodyBlock(raw: item.body)
          else if (item.type == 'fileChange')
            FileChangeBlock(item: item)
          else if (item.type == 'commandExecution')
            CommandExecutionBlock(item: item)
          else if (item.type == 'dynamicToolCall')
            ToolCallBlock(item: item)
          else if (item.type == 'collabAgentToolCall')
            DelegationBlock(item: item)
          else ...<Widget>[
            if (bodyPreview.isNotEmpty)
              Text(
                bodyPreview,
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Palette.mutedInk,
                  height: 1.45,
                ),
              ),
            if (item.auxiliary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class TimelineTypeTag extends StatelessWidget {
  const TimelineTypeTag({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.appOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label,
        style: roundedTextStyle(
          size: 11,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String get _label {
    switch (item.type) {
      case 'userMessage':
        return '用户';
      case 'agentMessage':
        return 'Agent';
      case 'fileChange':
        return '文件变更';
      case 'dynamicToolCall':
        return '工具调用';
      case 'collabAgentToolCall':
        return '委托';
      default:
        return item.title;
    }
  }

  Color get _color {
    switch (item.type) {
      case 'userMessage':
        return Palette.softBlue;
      case 'agentMessage':
        return Palette.accent;
      case 'fileChange':
        return Palette.accent2;
      case 'commandExecution':
        return Palette.warning;
      case 'dynamicToolCall':
        return Palette.softBlue;
      case 'collabAgentToolCall':
        return Palette.warning;
      default:
        return Palette.mutedInk;
    }
  }
}

class ToolCallBlock extends StatelessWidget {
  const ToolCallBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final tool = item.metadata['tool'] ?? '';
    final progress = item.metadata['progress'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tool.isNotEmpty)
          Text(
            tool,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.ink,
              fontFamily: 'monospace',
            ),
          ),
        if (tool.isNotEmpty && item.body.isNotEmpty) const SizedBox(height: 6),
        if (item.body.isNotEmpty)
          Text(
            item.body,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
        if (progress.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '进行中：$progress',
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w600,
              color: Palette.softBlue,
            ),
          ),
        ],
        if (item.auxiliary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
        ],
      ],
    );
  }
}

class DelegationBlock extends StatelessWidget {
  const DelegationBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final title = item.metadata['title'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w600,
              color: Palette.ink,
            ),
          ),
        if (title.isNotEmpty && item.body.isNotEmpty) const SizedBox(height: 6),
        if (item.body.isNotEmpty)
          HeadTailExcerptBlock(
            raw: item.body,
            head: 170,
            tail: 110,
            style: roundedTextStyle(
              size: 12,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              height: 1.45,
            ),
          ),
        if (item.auxiliary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
        ],
      ],
    );
  }
}

class FileChangeBlock extends StatelessWidget {
  const FileChangeBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final files = item.body
        .split('\n')
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toList();
    final visibleFiles = files.take(8).toList();
    final hiddenCount = files.length - visibleFiles.length;

    if (visibleFiles.isEmpty) {
      return Text(
        item.body,
        style: roundedTextStyle(
          size: 12,
          weight: FontWeight.w500,
          color: Palette.mutedInk,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...visibleFiles.map(
          (file) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.description_outlined,
                    size: 12,
                    color: Palette.accent2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file,
                    style: roundedTextStyle(
                      size: 12,
                      weight: FontWeight.w500,
                      color: Palette.ink,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hiddenCount > 0)
          Text(
            '… 还有 $hiddenCount 个文件',
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
            ),
          ),
      ],
    );
  }
}

class CommandExecutionBlock extends StatelessWidget {
  const CommandExecutionBlock({super.key, required this.item});

  final TurnItem item;

  @override
  Widget build(BuildContext context) {
    final cwd = item.metadata['cwd'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (cwd.isNotEmpty) ...<Widget>[
          Text(
            cwd,
            style: roundedTextStyle(
              size: 11,
              weight: FontWeight.w500,
              color: Palette.mutedInk,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (item.body.isNotEmpty) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.appOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.body,
                style: roundedTextStyle(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Palette.ink,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (item.auxiliary.isNotEmpty)
          TerminalOutputBlock(text: item.auxiliary, maxVisibleLines: 10),
      ],
    );
  }
}

class TerminalOutputBlock extends StatelessWidget {
  const TerminalOutputBlock({
    super.key,
    required this.text,
    this.maxVisibleLines,
  });

  final String text;
  final int? maxVisibleLines;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final visibleLines = maxVisibleLines == null
        ? lines
        : lines.take(maxVisibleLines!).toList();
    final hiddenLineCount = lines.length - visibleLines.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Palette.terminalBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ...visibleLines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Text(
                  line.isEmpty ? ' ' : line,
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Palette.terminalText,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            if (hiddenLineCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                child: Text(
                  '… 还有 $hiddenLineCount 行未显示',
                  style: roundedTextStyle(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Palette.terminalMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DiffBlock extends StatelessWidget {
  const DiffBlock({super.key, required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.appOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map(
                  (line) => Container(
                    color: _backgroundColor(line),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Text(
                      line.isEmpty ? ' ' : line,
                      style: roundedTextStyle(
                        size: 11,
                        weight: FontWeight.w500,
                        color: _foregroundColor(line),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(String line) {
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff ') ||
        line.startsWith('@@')) {
      return Palette.softBlue.appOpacity(0.10);
    }
    if (line.startsWith('+')) {
      return Palette.success.appOpacity(0.10);
    }
    if (line.startsWith('-')) {
      return Palette.danger.appOpacity(0.10);
    }
    return Colors.transparent;
  }

  Color _foregroundColor(String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return Palette.success;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return Palette.danger;
    }
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff ') ||
        line.startsWith('@@')) {
      return Palette.softBlue;
    }
    return Palette.ink;
  }
}
