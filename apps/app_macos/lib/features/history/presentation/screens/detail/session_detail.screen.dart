import 'dart:io';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/transcript_turns.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/widgets/summary_text.widget.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Note d'une réunion : la page entière défile (titre, puces, résumé,
/// coach, transcription par tour de parole). Actions dans la barre du haut.
class SessionDetailScreen extends ConsumerStatefulWidget {
  /// Crée l'écran pour [sessionId].
  const SessionDetailScreen({
    required this.sessionId,
    required this.onClose,
    super.key,
  });

  /// Identifiant de la note.
  final String sessionId;

  /// Retour à la page précédente (aussi appelé après suppression).
  final VoidCallback onClose;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  final TextEditingController _titleController = TextEditingController();

  SessionDetailViewModel get _vm => ref.read(
    sessionDetailViewModelProvider(sessionId: widget.sessionId).notifier,
  );

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SessionDetailState> async = ref.watch(
      sessionDetailViewModelProvider(sessionId: widget.sessionId),
    );
    final SessionDetailState? data = async.value;
    final bool loaded = data?.session != null && !async.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TopBar(
          onBack: widget.onClose,
          actions: loaded ? _actions() : const <Widget>[],
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, StackTrace st) => OatsEmptyState(
              icon: Icons.error_outline,
              message: LocaleKeys.common_error_generic.tr(),
            ),
            data: (SessionDetailState s) => s.session == null
                ? OatsEmptyState(
                    icon: Icons.description_outlined,
                    message: LocaleKeys.history_detail_no_session.tr(),
                  )
                : _content(s, s.session!),
          ),
        ),
      ],
    );
  }

  List<Widget> _actions() => <Widget>[
    OatsButton(
      icon: Icons.copy_outlined,
      label: LocaleKeys.history_detail_copy.tr(),
      onPressed: _copy,
    ),
    OatsButton(
      icon: Icons.file_download_outlined,
      label: LocaleKeys.history_detail_export_markdown.tr(),
      onPressed: _exportMarkdown,
    ),
    OatsButton(
      icon: Icons.auto_awesome_outlined,
      label: LocaleKeys.history_detail_summarize.tr(),
      onPressed: () => _vm.generateSummary(),
    ),
    OatsButton(
      icon: Icons.school_outlined,
      label: LocaleKeys.history_detail_english_coach.tr(),
      onPressed: () => _vm.analyzeEnglish(),
    ),
    OatsButton(
      icon: Icons.delete_outline,
      label: LocaleKeys.history_detail_delete.tr(),
      danger: true,
      onPressed: _confirmDelete,
    ),
  ];

  Widget _content(SessionDetailState state, SessionEntity session) {
    final Oats o = context.oats;
    final bool modelReady = ref.watch(
      ollamaSetupViewModelProvider.select((OllamaSetupState s) => s.isReady),
    );
    final List<int> speakers =
        state.speakers.map((SpeakerTurn t) => t.speaker).toSet().toList()
          ..sort();
    final String? duration = formatDuration(session.durationSeconds);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        OatsSpace.xxxl,
        OatsSpace.xxl,
        OatsSpace.xxxl,
        OatsSpace.xxxl * 2,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _title(state, session),
              const SizedBox(height: OatsSpace.md),
              Wrap(
                spacing: OatsSpace.xs + 2,
                runSpacing: OatsSpace.xs + 2,
                children: <Widget>[
                  OatsChip(
                    icon: Icons.calendar_today_outlined,
                    label: DateFormat(
                      'd MMM y · HH:mm',
                      'fr',
                    ).format(session.createdAt),
                  ),
                  if (duration != null)
                    OatsChip(icon: Icons.schedule_outlined, label: duration),
                  if (speakers.isNotEmpty)
                    Wrap(
                      key: const ValueKey<String>('session-detail-speakers'),
                      spacing: OatsSpace.xs + 2,
                      children: <Widget>[
                        for (final int n in speakers)
                          OatsChip(
                            icon: Icons.person_outline,
                            label: LocaleKeys.history_detail_speaker.tr(
                              args: <String>['${n + 1}'],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (!modelReady) ...<Widget>[
                const SizedBox(height: OatsSpace.xl),
                OatsNotice(
                  icon: Icons.auto_awesome_outlined,
                  message: LocaleKeys.llm_configure_model.tr(),
                ),
              ],
              if (state.isSummaryLoading || state.summary != null)
                _section(
                  title: LocaleKeys.history_detail_summary.tr(),
                  onDelete: state.summary == null
                      ? null
                      : () => _vm.deleteSummary(),
                  deleteLabel: LocaleKeys.history_detail_summary_delete.tr(),
                  child: state.isSummaryLoading
                      ? _Loading(LocaleKeys.history_detail_summary_loading.tr())
                      : SummaryText(state.summary!),
                ),
              if (state.isFeedbackLoading || state.feedback != null)
                _section(
                  title: LocaleKeys.history_detail_english_coach.tr(),
                  onDelete: state.feedback == null
                      ? null
                      : () => _vm.deleteFeedback(),
                  deleteLabel: LocaleKeys.history_detail_coach_delete.tr(),
                  child: state.isFeedbackLoading
                      ? _Loading(LocaleKeys.history_detail_coach_loading.tr())
                      : CoachFeedbackView(feedback: state.feedback!),
                ),
              _section(
                title: LocaleKeys.history_detail_transcript.tr(),
                child: state.segments.isEmpty
                    ? Text(
                        LocaleKeys.history_detail_transcript_empty.tr(),
                        style: o.small,
                      )
                    : Column(
                        key: const ValueKey<String>(
                          'session-detail-transcript',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final TranscriptTurn t in groupTurns(
                            state.segments,
                            state.speakers,
                          ))
                            _TurnView(turn: t),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(SessionDetailState state, SessionEntity session) {
    final Oats o = context.oats;
    if (state.isEditing) {
      return TextField(
        controller: _titleController..text = session.title,
        autofocus: true,
        style: o.display,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
        onSubmitted: (String value) => _vm.updateTitle(value),
      );
    }
    return GestureDetector(
      onDoubleTap: () => _vm.toggleEditing(),
      child: Semantics(
        header: true,
        child: Text(session.title, style: o.display),
      ),
    );
  }

  Widget _section({
    required String title,
    required Widget child,
    VoidCallback? onDelete,
    String? deleteLabel,
  }) {
    final Oats o = context.oats;
    return Padding(
      padding: const EdgeInsets.only(top: OatsSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.only(bottom: OatsSpace.sm),
            margin: const EdgeInsets.only(bottom: OatsSpace.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: o.line)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: o.heading),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    tooltip: deleteLabel,
                    iconSize: OatsIconSize.md,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, color: o.muted),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _vm.copyToClipboard()));
    _toast(LocaleKeys.history_detail_copied.tr());
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _exportMarkdown() async {
    final String content = _vm.exportMarkdown();
    if (content.isEmpty) return;
    try {
      final String home = Platform.environment['HOME'] ?? '';
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File('$home/Downloads/transcript_$stamp.md');
      await file.writeAsString(content);
      _toast(LocaleKeys.history_detail_exported.tr(args: <String>[file.path]));
    } catch (e) {
      _toast(LocaleKeys.history_detail_export_error.tr(args: <String>['$e']));
    }
  }

  Future<void> _confirmDelete() async {
    final Oats o = context.oats;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(LocaleKeys.history_detail_delete.tr()),
        content: Text(LocaleKeys.history_detail_delete_confirm.tr()),
        actions: <Widget>[
          OatsButton(
            label: LocaleKeys.common_action_cancel.tr(),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: o.danger,
              foregroundColor: o.background,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.common_action_delete.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _vm.deleteSession();
    if (mounted) widget.onClose();
  }
}

/// Barre du haut : Retour à gauche, actions à droite (passent à la ligne).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.actions});

  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.lg,
        vertical: OatsSpace.sm + 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: o.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OatsButton(
            icon: Icons.arrow_back,
            label: LocaleKeys.common_action_back.tr(),
            onPressed: onBack,
          ),
          const SizedBox(width: OatsSpace.lg),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: OatsSpace.xs + 2,
              runSpacing: OatsSpace.xs + 2,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un tour de parole : qui parle, quand, puis le texte.
class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn});

  final TranscriptTurn turn;

  String _label() {
    if (turn.source == AudioSource.input) {
      return LocaleKeys.history_detail_speaker_me.tr();
    }
    final int? n = turn.speaker;
    return n == null
        ? LocaleKeys.transcription_live_speaker_system.tr()
        : LocaleKeys.history_detail_speaker.tr(args: <String>['${n + 1}']);
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final Duration at = Duration(milliseconds: turn.startMs);
    final String time =
        '${at.inMinutes.toString().padLeft(2, '0')}:'
        '${(at.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: OatsSpace.lg + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                _label(),
                style: o.label.copyWith(
                  color: turn.source == AudioSource.input ? o.ink : o.muted,
                ),
              ),
              const SizedBox(width: OatsSpace.sm),
              Text(time, style: o.meta.copyWith(color: o.faint)),
            ],
          ),
          const SizedBox(height: OatsSpace.xs),
          for (final String p in turn.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: OatsSpace.xs),
              child: Text(p, style: o.body),
            ),
        ],
      ),
    );
  }
}

/// Ligne « en cours » : petit indicateur + libellé.
class _Loading extends StatelessWidget {
  const _Loading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const SizedBox(
        width: OatsIconSize.sm,
        height: OatsIconSize.sm,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      const SizedBox(width: OatsSpace.sm),
      Text(label, style: context.oats.small),
    ],
  );
}
