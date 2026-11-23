import 'dart:async';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart'
    show LiveAnswerModel;
import 'package:ici_transcript/application/services/llm/meeting_ai.dart';
import 'package:rxdart/rxdart.dart';

/// Écart minimal entre deux requêtes du coach en direct.
const Duration kLiveCoachInterval = Duration(seconds: 20);

/// Ce que le coach en direct a trouvé pendant la note [sessionId].
class LiveCoachSnapshot {
  /// Crée un instantané.
  const LiveCoachSnapshot({
    this.sessionId,
    this.corrections = const <EnglishCorrectionEntity>[],
    this.unavailable = false,
  });

  /// Note concernée ; null avant le premier démarrage.
  final String? sessionId;

  /// Corrections, dans l'ordre où elles ont été trouvées.
  final List<EnglishCorrectionEntity> corrections;

  /// Dernier lot non envoyé (pas de fournisseur en ligne) ou en échec.
  final bool unavailable;
}

/// Coach anglais EN DIRECT : les phrases anglaises finales de l'utilisateur
/// partent par lots, au plus une requête par [interval] (la première sans
/// attendre), et seulement vers un fournisseur en ligne : une génération
/// locale ralentit la transcription (1,8 s → 6–24 s mesurés).
///
/// Ne bloque jamais la transcription : [onSegmentFinalized] est synchrone,
/// un échec ne fait que poser `unavailable`, ses phrases restent pour la
/// passe d'après l'appel (pas dans [coachedSegmentIds]).
class LiveCoachService {
  /// Crée le service ; le modèle est relu à chaque lot.
  LiveCoachService({
    required Future<LiveAnswerModel?> Function() resolveModel,
    this.interval = kLiveCoachInterval,
  }) : _resolveModel = resolveModel;

  final Future<LiveAnswerModel?> Function() _resolveModel;

  /// Écart minimal entre deux requêtes.
  final Duration interval;

  final Log _log = Log.named('LiveCoachService');
  final BehaviorSubject<LiveCoachSnapshot> _subject =
      BehaviorSubject<LiveCoachSnapshot>.seeded(const LiveCoachSnapshot());
  final List<TranscriptSegmentEntity> _pending = <TranscriptSegmentEntity>[];
  final Set<String> _coached = <String>{};

  bool _running = false;
  bool _busy = false;
  Timer? _cooldown;
  StreamSubscription<String>? _request;
  int _run = 0;

  /// Dernier état publié.
  LiveCoachSnapshot get snapshot => _subject.value;

  /// [snapshot] à chaque changement.
  Stream<LiveCoachSnapshot> get snapshots => _subject.stream;

  /// Phrases déjà corrigées en direct (la passe d'après l'appel les saute).
  Set<String> get coachedSegmentIds => Set<String>.unmodifiable(_coached);

  /// Ouvre la note [sessionId] : l'état précédent est oublié.
  void start(String sessionId) {
    _halt();
    _coached.clear();
    _running = true;
    _subject.add(LiveCoachSnapshot(sessionId: sessionId));
  }

  /// Ferme la note : la requête en vol est abandonnée, ce qui a été trouvé
  /// reste lisible jusqu'au prochain [start].
  Future<void> stop() async => _halt();

  /// Libère le service (fin de l'app).
  Future<void> dispose() async {
    _halt();
    await _subject.close();
  }

  /// Phrase finale d'une des deux sources ; seules les phrases anglaises de
  /// l'utilisateur sont gardées.
  void onSegmentFinalized(TranscriptSegmentEntity segment) {
    if (!_running || !isCoachable(segment)) return;
    _pending.add(segment);
    _flush();
  }

  void _halt() {
    _running = false;
    _run++;
    _cooldown?.cancel();
    _cooldown = null;
    unawaited(_request?.cancel());
    _request = null;
    _busy = false;
    _pending.clear();
  }

  void _flush() {
    if (!_running || _busy || _cooldown != null || _pending.isEmpty) return;
    final List<CoachLine> batch = coachBatches(_pending).first;
    final Set<String> ids = batch.map((CoachLine l) => l.id).toSet();
    _pending.removeWhere((TranscriptSegmentEntity s) => ids.contains(s.id));
    _busy = true;
    _cooldown = Timer(interval, () {
      _cooldown = null;
      _flush();
    });
    unawaited(_send(batch, ++_run));
  }

  Future<void> _send(List<CoachLine> batch, int run) async {
    final LiveAnswerModel? model;
    try {
      model = await _resolveModel();
    } on Object catch (e) {
      return _done(run, error: e);
    }
    if (run != _run) return;
    if (model == null || model.isLocal) {
      // Rien ne part : le modèle local ralentirait la transcription.
      return _done(run, error: 'aucun fournisseur en ligne');
    }
    final StringBuffer raw = StringBuffer();
    _request = model.provider
        .streamChat(coachRequest(batch, preferLowLatency: true))
        .listen(
          raw.write,
          onError: (Object e) => _done(run, error: e),
          onDone: () {
            try {
              final EnglishFeedbackEntity found = parseFeedback('$raw');
              _done(run, batch: batch, found: found);
            } on Object catch (e) {
              _done(run, error: e);
            }
          },
          cancelOnError: true,
        );
  }

  void _done(
    int run, {
    List<CoachLine>? batch,
    EnglishFeedbackEntity? found,
    Object? error,
  }) {
    if (run != _run) return;
    _request = null;
    _busy = false;
    final LiveCoachSnapshot s = snapshot;
    if (error != null) {
      _log.warning('Coach en direct indisponible : $error');
      _subject.add(
        LiveCoachSnapshot(
          sessionId: s.sessionId,
          corrections: s.corrections,
          unavailable: true,
        ),
      );
    } else {
      _coached.addAll(batch!.map((CoachLine l) => l.id));
      _subject.add(
        LiveCoachSnapshot(
          sessionId: s.sessionId,
          corrections: <EnglishCorrectionEntity>[
            ...s.corrections,
            ...timedCorrections(found!, batch),
          ],
        ),
      );
    }
    _flush();
  }
}
