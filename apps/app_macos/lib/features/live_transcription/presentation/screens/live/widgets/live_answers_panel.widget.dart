import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/question_answer.widget.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Zone « Questions » de l'écran en direct : les questions des autres, la
/// réponse proposée au fil de l'eau, et les actions (Copier, Réessayer,
/// Ignorer, Proposer une réponse, Répondre).
class LiveAnswersPanel extends ConsumerWidget {
  /// Crée la zone.
  const LiveAnswersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Oats o = context.oats;
    final LiveAnswersService service = ref.watch(liveAnswersServiceProvider);
    return StreamBuilder<List<LiveQuestion>>(
      stream: service.questionsStream,
      initialData: service.questions,
      builder: (BuildContext context, AsyncSnapshot<List<LiveQuestion>> snap) {
        final List<LiveQuestion> questions =
            (snap.data ?? const <LiveQuestion>[]).reversed.toList();
        final bool onDemand = questions.any((LiveQuestion q) => q.onDemand);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OatsSpace.lg,
                OatsSpace.md,
                OatsSpace.md,
                OatsSpace.md,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        LocaleKeys.live_answers_title.tr(),
                        style: o.heading,
                      ),
                    ),
                  ),
                  OatsButton(
                    icon: Icons.reply_outlined,
                    label: LocaleKeys.live_answers_answer_latest.tr(),
                    onPressed: service.answerLatestFromOthers,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: o.line),
            if (onDemand)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OatsSpace.lg,
                  OatsSpace.md,
                  OatsSpace.lg,
                  0,
                ),
                child: Text(
                  LocaleKeys.live_answers_local_manual_hint.tr(),
                  style: o.small,
                ),
              ),
            Expanded(
              child: questions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(OatsSpace.lg),
                      child: Text(
                        LocaleKeys.live_answers_empty.tr(),
                        style: o.small,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OatsSpace.lg,
                        vertical: OatsSpace.md,
                      ),
                      itemCount: questions.length,
                      separatorBuilder: (_, _) => Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: OatsSpace.md,
                        ),
                        child: Divider(height: 1, thickness: 1, color: o.line),
                      ),
                      itemBuilder: (BuildContext context, int i) =>
                          _QuestionCard(
                            question: questions[i],
                            service: service,
                          ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.service});

  final LiveQuestion question;
  final LiveAnswersService service;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final LiveQuestion q = question;
    final (String?, QuestionStatusTone) status = switch (q.status) {
      LiveQuestionStatus.answering when q.answer.isEmpty => (
        LocaleKeys.live_answers_answering.tr(),
        QuestionStatusTone.live,
      ),
      LiveQuestionStatus.declined => (
        LocaleKeys.live_answers_declined.tr(),
        QuestionStatusTone.neutral,
      ),
      LiveQuestionStatus.failed => (
        _failureKey(q.failure).tr(),
        QuestionStatusTone.danger,
      ),
      LiveQuestionStatus.needsModel => (
        LocaleKeys.llm_configure_model.tr(),
        QuestionStatusTone.neutral,
      ),
      _ => (null, QuestionStatusTone.neutral),
    };
    Widget icon(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: OatsIconSize.md,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, color: o.muted),
        );
    return QuestionAnswerView(
      question: q,
      speakerLabel: _speaker(q),
      status: status.$1,
      statusTone: status.$2,
      truncatedLabel: LocaleKeys.live_answers_truncated.tr(),
      actions: <Widget>[
        if (q.status == LiveQuestionStatus.answered)
          icon(
            Icons.content_copy_outlined,
            LocaleKeys.live_answers_copy.tr(),
            () => _copy(context),
          ),
        icon(
          Icons.close,
          LocaleKeys.live_answers_dismiss.tr(),
          () => service.dismiss(q.id),
        ),
      ],
      footer: <Widget>[
        if (q.status == LiveQuestionStatus.failed ||
            q.status == LiveQuestionStatus.needsModel)
          OatsButton(
            icon: Icons.refresh,
            label: LocaleKeys.common_action_retry.tr(),
            onPressed: () => service.retry(q.id),
          ),
        if (q.status == LiveQuestionStatus.detected)
          OatsButton(
            icon: Icons.auto_awesome_outlined,
            label: LocaleKeys.live_answers_answer.tr(),
            onPressed: () => service.retry(q.id),
          ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    await Clipboard.setData(
      ClipboardData(text: answerPlainText(question.answer)),
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(LocaleKeys.live_answers_copied.tr()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static String _speaker(LiveQuestion q) => q.source == AudioSource.input
      ? LocaleKeys.transcription_live_speaker_me.tr()
      : q.speaker == null
      ? LocaleKeys.transcription_live_speaker_system.tr()
      : LocaleKeys.transcription_live_speaker_n.tr(
          args: <String>['${q.speaker! + 1}'],
        );

  // Le générateur d'easy_localization ne crée pas de constante pour une clé
  // nommée « other » (mot réservé des pluriels).
  static const String _otherErrorKey = 'live_answers.error.other';

  static String _failureKey(LiveAnswerFailure? f) => switch (f) {
    LiveAnswerFailure.invalidKey => LocaleKeys.live_answers_error_invalid_key,
    LiveAnswerFailure.rateLimited => LocaleKeys.live_answers_error_rate_limited,
    LiveAnswerFailure.unreachable => LocaleKeys.live_answers_error_unreachable,
    LiveAnswerFailure.malformed => LocaleKeys.live_answers_error_malformed,
    LiveAnswerFailure.other || null => _otherErrorKey,
  };
}
