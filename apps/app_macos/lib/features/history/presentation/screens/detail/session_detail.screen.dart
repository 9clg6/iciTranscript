import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/transcript_line.widget.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Ecran de detail d'une session de transcription.
///
/// Affiche le titre editable, la date et la duree, les boutons d'action
/// (Copier, Exporter, Resumer, Supprimer) et la transcription complete.
@RoutePage()
class SessionDetailScreen extends ConsumerStatefulWidget {
  /// Cree une instance de [SessionDetailScreen].
  const SessionDetailScreen({
    @PathParam('sessionId') required this.sessionId,
    this.onClose,
    super.key,
  });

  /// Identifiant de la session a afficher.
  final String sessionId;

  /// Callback pour fermer l'overlay (optionnel, utilisé hors routing).
  final VoidCallback? onClose;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _formatDuration(int? durationSeconds) {
    if (durationSeconds == null) return '';
    final int hours = durationSeconds ~/ 3600;
    final int minutes = (durationSeconds % 3600) ~/ 60;
    final int seconds = durationSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  String _formatDate(DateTime date) {
    return DateFormat('d MMMM yyyy, HH:mm', 'fr').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SessionDetailState> asyncState = ref.watch(
      sessionDetailViewModelProvider(sessionId: widget.sessionId),
    );
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) =>
          Center(child: Text(LocaleKeys.common_error_generic.tr())),
      data: (SessionDetailState state) {
        if (state.session == null) {
          return Center(
            child: Text(
              LocaleKeys.history_detail_no_session.tr(),
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return _buildContent(state, colorScheme, textTheme);
      },
    );
  }

  Widget _buildContent(
    SessionDetailState state,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final session = state.session!;

    return Column(
      children: <Widget>[
        // Header with title and metadata
        _buildHeader(state, session, colorScheme, textTheme),
        // Action buttons bar
        _buildActionBar(colorScheme),
        // Divider
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        // Resume IA (genere a la demande)
        if (state.isSummaryLoading || state.summary != null) ...<Widget>[
          const Gap(16),
          _buildSummaryPanel(state, colorScheme, textTheme),
        ],
        // Retour du coach d'anglais (genere a la demande)
        if (state.isFeedbackLoading || state.feedback != null) ...<Widget>[
          const Gap(16),
          _buildCoachPanel(state, colorScheme, textTheme),
        ],
        // Interlocuteurs (diarization post-session)
        if (state.speakers.isNotEmpty) ...<Widget>[
          const Gap(16),
          _buildSpeakersPanel(state, colorScheme, textTheme),
        ],
        // Transcript content
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            itemCount: state.segments.length,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TranscriptLineWidget(segment: state.segments[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCoachPanel(
    SessionDetailState state,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(48, 0, 48, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.school_outlined,
                size: 16,
                color: colorScheme.secondary,
              ),
              const Gap(8),
              Text(
                'Coach d\'anglais',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (state.feedback != null)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  ),
                  tooltip: 'Supprimer le retour',
                  onPressed: () {
                    ref
                        .read(
                          sessionDetailViewModelProvider(
                            sessionId: widget.sessionId,
                          ).notifier,
                        )
                        .deleteFeedback();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const Gap(12),
          if (state.isFeedbackLoading)
            _loadingRow('Analyse de votre anglais...', colorScheme, textTheme)
          else if (state.feedback != null)
            CoachFeedbackView(feedback: state.feedback!),
        ],
      ),
    );
  }

  Widget _buildSummaryPanel(
    SessionDetailState state,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(48, 0, 48, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const Gap(8),
              Text(
                'Résumé IA',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (state.summary != null)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  ),
                  tooltip: 'Supprimer le résumé',
                  onPressed: () {
                    ref
                        .read(
                          sessionDetailViewModelProvider(
                            sessionId: widget.sessionId,
                          ).notifier,
                        )
                        .deleteSummary();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const Gap(12),
          if (state.isSummaryLoading)
            _loadingRow('Génération du résumé...', colorScheme, textTheme)
          else if (state.summary != null)
            Text(
              state.summary!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeakersPanel(
    SessionDetailState state,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(48, 0, 48, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.groups_outlined, size: 16, color: colorScheme.tertiary),
              const Gap(8),
              Text(
                'Interlocuteurs',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Gap(12),
          for (final SpeakerTurn turn in state.speakers) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Interlocuteur ${turn.speaker + 1}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.tertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    turn.text,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loadingRow(
    String label,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const Gap(8),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    SessionDetailState state,
    dynamic session,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Editable title
          if (state.isEditing) ...<Widget>[
            TextField(
              controller: _titleController..text = session.title,
              autofocus: true,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onSubmitted: (String value) {
                ref
                    .read(
                      sessionDetailViewModelProvider(
                        sessionId: widget.sessionId,
                      ).notifier,
                    )
                    .updateTitle(value);
              },
            ),
          ] else ...<Widget>[
            GestureDetector(
              onDoubleTap: () {
                ref
                    .read(
                      sessionDetailViewModelProvider(
                        sessionId: widget.sessionId,
                      ).notifier,
                    )
                    .toggleEditing();
              },
              child: Text(
                session.title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
          const Gap(8),
          // Date and duration
          Row(
            children: <Widget>[
              Icon(
                Icons.calendar_today,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const Gap(4),
              Text(
                _formatDate(session.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(16),
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const Gap(4),
              Text(
                '${LocaleKeys.history_detail_duration.tr()}: '
                '${_formatDuration(session.durationSeconds)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
      child: Row(
        children: <Widget>[
          // Copy
          _ActionButton(
            icon: Icons.copy_outlined,
            label: LocaleKeys.history_detail_copy.tr(),
            onPressed: () async {
              final String text = ref
                  .read(
                    sessionDetailViewModelProvider(
                      sessionId: widget.sessionId,
                    ).notifier,
                  )
                  .copyToClipboard();
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(LocaleKeys.history_detail_copied.tr()),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            colorScheme: colorScheme,
          ),
          const Gap(8),
          // Export Markdown
          _ActionButton(
            icon: Icons.file_download_outlined,
            label: LocaleKeys.history_detail_export_markdown.tr(),
            onPressed: () => _exportMarkdown(),
            colorScheme: colorScheme,
          ),
          const Gap(8),
          // Resumer
          _ActionButton(
            icon: Icons.auto_awesome_outlined,
            label: LocaleKeys.history_detail_summarize.tr(),
            onPressed: () {
              ref
                  .read(
                    sessionDetailViewModelProvider(
                      sessionId: widget.sessionId,
                    ).notifier,
                  )
                  .generateSummary();
            },
            colorScheme: colorScheme,
          ),
          const Gap(8),
          // Coach d'anglais
          _ActionButton(
            icon: Icons.school_outlined,
            label: 'Coach d\'anglais',
            onPressed: () {
              ref
                  .read(
                    sessionDetailViewModelProvider(
                      sessionId: widget.sessionId,
                    ).notifier,
                  )
                  .analyzeEnglish();
            },
            colorScheme: colorScheme,
          ),
          const Spacer(),
          // Delete
          _ActionButton(
            icon: Icons.delete_outline,
            label: LocaleKeys.history_detail_delete.tr(),
            onPressed: () => _confirmDelete(colorScheme),
            colorScheme: colorScheme,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Future<void> _exportMarkdown() async {
    final String content = ref
        .read(
          sessionDetailViewModelProvider(sessionId: widget.sessionId).notifier,
        )
        .exportMarkdown();
    if (content.isEmpty) return;

    try {
      final String home = Platform.environment['HOME'] ?? '';
      final Directory downloadsDir = Directory('$home/Downloads');
      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File(
        '${downloadsDir.path}/transcript_$timestamp.md',
      );
      await file.writeAsString(content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exporté : ${file.path}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(ColorScheme colorScheme) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(LocaleKeys.history_detail_delete.tr()),
        content: Text(LocaleKeys.history_detail_delete_confirm.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.common_action_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(LocaleKeys.common_action_delete.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(
            sessionDetailViewModelProvider(
              sessionId: widget.sessionId,
            ).notifier,
          )
          .deleteSession();
      if (mounted) {
        widget.onClose?.call();
      }
    }
  }
}

/// Bouton d'action reutilisable pour la barre d'actions.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = isDestructive
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;

    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: foregroundColor),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
