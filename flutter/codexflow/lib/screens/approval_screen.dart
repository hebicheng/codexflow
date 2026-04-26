import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../state/app_model.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) {
          return;
        }
        unawaited(context.read<AppModel>().refreshDashboard());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final approvals = model.selectedAgentApprovals;
    final supportsApprovals =
        model.selectedAgentOption?.capabilities.supportsApprovals ?? true;
    return Scaffold(
      backgroundColor: Palette.canvas,
      appBar: AppBar(
        title: Text('审批',
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
              PanelCard(
                compact: true,
                child: Text(
                  supportsApprovals
                      ? '这里处理当前 Agent 发来的命令审批、文件变更审批、权限审批，以及需要你回答的问题。'
                      : '当前 Agent 不提供审批事件流，这里暂时不会出现待审批项目。',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Palette.mutedInk,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (approvals.isEmpty)
                PanelCard(
                  compact: true,
                  child: Text(
                    supportsApprovals ? '当前没有待处理审批。' : '当前 Agent 不支持审批能力。',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Palette.mutedInk,
                    ),
                  ),
                )
              else
                ApprovalList(
                  approvals: approvals,
                  showSessionLabel: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionApprovalSheet extends StatelessWidget {
  const SessionApprovalSheet({
    super.key,
    required this.title,
    required this.approvals,
  });

  final String title;
  final List<PendingRequestView> approvals;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.6,
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
                    title: Text(title,
                        style: roundedTextStyle(
                            size: 17, weight: FontWeight.w600)),
                    centerTitle: true,
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          '关闭',
                          style: roundedTextStyle(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Palette.softBlue),
                        ),
                      ),
                    ],
                  ),
                  body: PageScaffold(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: <Widget>[
                        if (approvals.isEmpty)
                          const PanelCard(
                            compact: true,
                            child: Text(
                              '当前没有待处理审批。',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Palette.mutedInk,
                              ),
                            ),
                          )
                        else
                          ApprovalList(
                              approvals: approvals, showSessionLabel: false),
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
}

class ApprovalList extends StatelessWidget {
  const ApprovalList({
    super.key,
    required this.approvals,
    required this.showSessionLabel,
  });

  final List<PendingRequestView> approvals;
  final bool showSessionLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: approvals
          .map(
            (approval) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ApprovalCard(
                approval: approval,
                showSessionLabel: showSessionLabel,
              ),
            ),
          )
          .toList(),
    );
  }
}

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.approval,
    required this.showSessionLabel,
  });

  final PendingRequestView approval;
  final bool showSessionLabel;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      compact: true,
      child: ApprovalCardBody(
        approval: approval,
        showSessionLabel: showSessionLabel,
        embedded: false,
      ),
    );
  }
}

class ApprovalCardBody extends StatefulWidget {
  const ApprovalCardBody({
    super.key,
    required this.approval,
    required this.showSessionLabel,
    required this.embedded,
  });

  final PendingRequestView approval;
  final bool showSessionLabel;
  final bool embedded;

  @override
  State<ApprovalCardBody> createState() => _ApprovalCardBodyState();
}

class _ApprovalCardBodyState extends State<ApprovalCardBody> {
  late final TextEditingController _replyController;

  @override
  void initState() {
    super.initState();
    _replyController = TextEditingController();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final approval = widget.approval;
    return Container(
      padding: widget.embedded ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: widget.embedded
          ? BoxDecoration(
              color: Palette.warning.appOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.warning.appOpacity(0.18)),
            )
          : null,
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
                      _kindTitle(approval.kind),
                      style:
                          roundedTextStyle(size: 16, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      approval.summary,
                      style: roundedTextStyle(
                          size: 13,
                          weight: FontWeight.w500,
                          color: Palette.mutedInk,
                          height: 1.45),
                    ),
                    if (widget.showSessionLabel) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        _sessionLabel(model, approval),
                        style:
                            roundedTextStyle(size: 12, weight: FontWeight.w500),
                      ),
                    ],
                    if (approval.reason.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        approval.reason,
                        style: roundedTextStyle(
                            size: 12,
                            weight: FontWeight.w500,
                            color: Palette.mutedInk),
                      ),
                    ],
                    if (_firstQuestion(approval) != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        _firstQuestion(approval)!.question,
                        style:
                            roundedTextStyle(size: 12, weight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(status: approval.kind, waiting: true),
            ],
          ),
          const SizedBox(height: 12),
          if (approval.kind == 'userInput')
            _buildUserInputActions(context)
          else
            _buildChoiceButtons(context),
        ],
      ),
    );
  }

  Widget _buildUserInputActions(BuildContext context) {
    final question = _firstQuestion(widget.approval);
    final buttons = question?.options ?? const <ApprovalQuestionOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (buttons.isNotEmpty)
          ...buttons.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ActionButton(
                title: option.label,
                background: Palette.softBlue.appOpacity(0.15),
                foreground: Palette.softBlue,
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await context.read<AppModel>().resolve(
                        approval: widget.approval,
                        action: ApprovalAction.submitText(option.label),
                      );
                },
              ),
            ),
          ),
        CodexTextField(
          controller: _replyController,
          hintText: 'Reply',
          autocapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        ActionButton(
          title: '提交回复',
          background: Palette.accent,
          foreground: Colors.white,
          onPressed: () async {
            FocusScope.of(context).unfocus();
            await context.read<AppModel>().resolve(
                  approval: widget.approval,
                  action: ApprovalAction.submitText(_replyController.text),
                );
          },
        ),
      ],
    );
  }

  Widget _buildChoiceButtons(BuildContext context) {
    final buttons = _choiceButtons(widget.approval);
    return Column(
      children: buttons
          .map(
            (button) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ActionButton(
                title: button.title,
                background: button.background,
                foreground: button.foreground,
                onPressed: () async {
                  await context.read<AppModel>().resolve(
                        approval: widget.approval,
                        action: button.action,
                      );
                },
              ),
            ),
          )
          .toList(),
    );
  }

  String _sessionLabel(AppModel model, PendingRequestView approval) {
    final session = model.dashboard.sessions.cast<SessionSummary?>().firstWhere(
          (item) => item?.id == approval.threadId,
          orElse: () => null,
        );
    if (session != null) {
      return '会话：${session.displayName}';
    }
    return '会话：${approval.threadId}';
  }

  String _kindTitle(String kind) {
    switch (kind) {
      case 'command':
        return '命令审批';
      case 'fileChange':
        return '文件变更审批';
      case 'permissions':
        return '权限审批';
      case 'userInput':
        return '需要你的回复';
      default:
        return kind;
    }
  }

  ApprovalQuestion? _firstQuestion(PendingRequestView approval) {
    final questions = asList(approval.params['questions']);
    for (final value in questions) {
      final object = asMap(value);
      final id = asString(object['id'], UniqueKey().toString());
      final question = asString(object['question']).isNotEmpty
          ? asString(object['question'])
          : asString(object['prompt']);
      final options = asList(object['options'])
          .map((option) => asMap(option))
          .map(
            (option) => ApprovalQuestionOption(
              label: asString(option['label']),
              description: asString(option['description']),
            ),
          )
          .where((option) => option.label.isNotEmpty)
          .toList();
      return ApprovalQuestion(id: id, question: question, options: options);
    }
    return null;
  }

  List<_ApprovalChoiceButton> _choiceButtons(PendingRequestView approval) {
    final availableCommandButtons = _availableDecisionButtons(approval);
    if (approval.kind == 'command' && availableCommandButtons.isNotEmpty) {
      return availableCommandButtons;
    }

    final effectiveChoices = approval.choices.isEmpty
        ? _fallbackChoices(approval.kind)
        : approval.choices;
    return effectiveChoices.map((choice) {
      switch (choice) {
        case 'accept':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '允许一次',
            background: Palette.accent,
            foreground: Colors.white,
          );
        case 'acceptForSession':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '本会话内允许',
            background: Palette.softBlue.appOpacity(0.15),
            foreground: Palette.softBlue,
          );
        case 'decline':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '拒绝',
            background: Palette.danger.appOpacity(0.12),
            foreground: Palette.danger,
          );
        case 'cancel':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '取消',
            background: Palette.shell,
            foreground: Palette.mutedInk,
          );
        case 'session':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '授权到会话',
            background: Palette.softBlue,
            foreground: Colors.white,
          );
        case 'turn':
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: '仅本轮授权',
            background: Palette.accent,
            foreground: Colors.white,
          );
        default:
          return _ApprovalChoiceButton(
            action: ApprovalAction.choice(choice),
            title: choice,
            background: Palette.shell,
            foreground: Palette.ink,
          );
      }
    }).toList();
  }

  List<_ApprovalChoiceButton> _availableDecisionButtons(
      PendingRequestView approval) {
    return asList(approval.params['availableDecisions'])
        .map(_commandDecisionButton)
        .whereType<_ApprovalChoiceButton>()
        .toList();
  }

  _ApprovalChoiceButton? _commandDecisionButton(dynamic decision) {
    if (decision is String) {
      switch (decision) {
        case 'accept':
          return _ApprovalChoiceButton(
            action: ApprovalAction.decision(decision),
            title: '允许一次',
            background: Palette.accent,
            foreground: Colors.white,
          );
        case 'acceptForSession':
          return _ApprovalChoiceButton(
            action: ApprovalAction.decision(decision),
            title: '本会话内允许',
            background: Palette.softBlue.appOpacity(0.15),
            foreground: Palette.softBlue,
          );
        case 'decline':
          return _ApprovalChoiceButton(
            action: ApprovalAction.decision(decision),
            title: '拒绝',
            background: Palette.danger.appOpacity(0.12),
            foreground: Palette.danger,
          );
        case 'cancel':
          return _ApprovalChoiceButton(
            action: ApprovalAction.decision(decision),
            title: '取消并中断本轮',
            background: Palette.shell,
            foreground: Palette.mutedInk,
          );
        default:
          return _ApprovalChoiceButton(
            action: ApprovalAction.decision(decision),
            title: decision,
            background: Palette.shell,
            foreground: Palette.ink,
          );
      }
    }

    final object = asMap(decision);
    if (object.containsKey('acceptWithExecpolicyAmendment')) {
      return _ApprovalChoiceButton(
        action: ApprovalAction.decision(
          <String, dynamic>{
            'acceptWithExecpolicyAmendment':
                object['acceptWithExecpolicyAmendment'],
          },
        ),
        title: '允许并记住这类命令',
        background: Palette.softBlue,
        foreground: Colors.white,
      );
    }

    final amendmentWrapper = asMap(object['applyNetworkPolicyAmendment']);
    final amendment = asMap(amendmentWrapper['network_policy_amendment']);
    if (amendment.isNotEmpty) {
      final host = asString(amendment['host'], '该主机');
      final action = asString(amendment['action']);
      final isAllow = action == 'allow';
      return _ApprovalChoiceButton(
        action: ApprovalAction.decision(
          <String, dynamic>{
            'applyNetworkPolicyAmendment': <String, dynamic>{
              'network_policy_amendment': amendment,
            },
          },
        ),
        title: isAllow ? '允许并记住 $host' : '拒绝并记住 $host',
        background: isAllow
            ? Palette.softBlue.appOpacity(0.15)
            : Palette.danger.appOpacity(0.12),
        foreground: isAllow ? Palette.softBlue : Palette.danger,
      );
    }

    if (object.isNotEmpty) {
      final key = object.keys.first;
      return _ApprovalChoiceButton(
        action: ApprovalAction.decision(object),
        title: key,
        background: Palette.shell,
        foreground: Palette.ink,
      );
    }

    return null;
  }

  List<String> _fallbackChoices(String kind) {
    switch (kind) {
      case 'command':
      case 'fileChange':
        return const <String>[
          'accept',
          'acceptForSession',
          'decline',
          'cancel'
        ];
      case 'permissions':
        return const <String>['session', 'turn', 'decline'];
      default:
        return const <String>['decline'];
    }
  }
}

class _ApprovalChoiceButton {
  _ApprovalChoiceButton({
    required this.action,
    required this.title,
    required this.background,
    required this.foreground,
  });

  final ApprovalAction action;
  final String title;
  final Color background;
  final Color foreground;
}
