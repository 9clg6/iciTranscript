import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/application/services/summary.service.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'coach_overview.provider.g.dart';

/// Une note passée au coach et son retour.
typedef CoachNote = ({SessionEntity session, EnglishFeedbackEntity feedback});

/// Une catégorie de correction (telle que rangée) vue dans [notes] notes.
typedef RecurringMistake = ({String category, int notes});

/// Page « Coach anglais » : notes passées au coach, erreurs récurrentes.
typedef CoachOverview = ({
  List<CoachNote> notes,
  List<RecurringMistake> recurring,
});

/// Une catégorie est récurrente à partir de ce nombre de notes.
const int kRecurringMinNotes = 3;

/// Lu à l'ouverture de la page, dans `summaries.content` (pas de
/// migration). Une erreur de lecture se relance à la main (Réessayer).
@Riverpod(retry: _noRetry)
Future<CoachOverview> coachOverview(Ref ref) async {
  final List<SessionEntity> sessions = await ref
      .read(sessionRepositoryProvider)
      .getAll();
  final SummaryService summaries = ref.read(summaryServiceProvider);
  final List<CoachNote> notes = <CoachNote>[];
  for (final SessionEntity s in sessions) {
    final EnglishFeedbackEntity? feedback = SessionAnalysis.fromStored(
      await summaries.getSummaryForSession(s.id),
    ).feedback;
    if (feedback != null) notes.add((session: s, feedback: feedback));
  }
  return buildCoachOverview(notes);
}

Duration? _noRetry(int retryCount, Object error) => null;

/// Ordre de la page et erreurs récurrentes (règle pure).
///
/// Jours du plus récent au plus ancien ; dans un jour, les notes avec des
/// corrections d'abord, puis la plus récente. Récurrente : une même
/// catégorie (« grammar » = « Grammaire ») dans [kRecurringMinNotes] notes
/// ou plus, une note comptant une fois.
CoachOverview buildCoachOverview(List<CoachNote> notes) {
  DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
  final List<CoachNote> sorted = <CoachNote>[...notes]
    ..sort((CoachNote a, CoachNote b) {
      final int byDay = dayOf(
        b.session.createdAt,
      ).compareTo(dayOf(a.session.createdAt));
      if (byDay != 0) return byDay;
      final bool aHas = a.feedback.corrections.isNotEmpty;
      final bool bHas = b.feedback.corrections.isNotEmpty;
      if (aHas != bHas) return aHas ? -1 : 1;
      return b.session.createdAt.compareTo(a.session.createdAt);
    });
  // Clé commune (« grammar » = « Grammaire ») → nombre de notes, et une
  // catégorie telle que rangée, pour l'afficher.
  final Map<String, int> count = <String, int>{};
  final Map<String, String> shown = <String, String>{};
  for (final CoachNote n in notes) {
    final Map<String, String> categories = <String, String>{
      for (final EnglishCorrectionEntity c in n.feedback.corrections)
        coachCategoryKey(c.category) ?? c.category.trim().toLowerCase():
            c.category,
    };
    categories.forEach((String key, String category) {
      count[key] = (count[key] ?? 0) + 1;
      shown.putIfAbsent(key, () => category);
    });
  }
  final List<RecurringMistake> recurring = <RecurringMistake>[
    for (final MapEntry<String, int> e in count.entries)
      if (e.value >= kRecurringMinNotes)
        (category: shown[e.key]!, notes: e.value),
  ]..sort((RecurringMistake a, RecurringMistake b) => b.notes - a.notes);
  return (notes: sorted, recurring: recurring);
}
