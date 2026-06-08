import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';

/// Un tour de parole d'un interlocuteur du meeting (résultat de diarization).
class SpeakerTurn {
  const SpeakerTurn({
    required this.speaker,
    required this.start,
    required this.end,
    required this.text,
  });

  /// Index de l'interlocuteur (0, 1, 2, …) → affiché "Interlocuteur N+1".
  final int speaker;

  /// Début / fin du tour en secondes.
  final double start;
  final double end;

  /// Transcription du tour.
  final String text;

  factory SpeakerTurn.fromJson(Map<String, dynamic> j) => SpeakerTurn(
        speaker: (j['speaker'] as num?)?.toInt() ?? 0,
        start: (j['start'] as num?)?.toDouble() ?? 0,
        end: (j['end'] as num?)?.toDouble() ?? 0,
        text: j['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'speaker': speaker,
        'start': start,
        'end': end,
        'text': text,
      };
}

/// Enveloppe stockée dans `summaries.content` pour conserver dans une seule
/// colonne (pas de migration DB) :
/// - le résumé IA,
/// - le retour du coach d'anglais,
/// - la transcription propre post-session (micro = MOI + interlocuteurs).
///
/// Format : `{"summary":?, "feedback":?, "micText":?, "speakers":[…]}`.
/// Rétro-compatible avec : JSON coach brut, texte libre.
class SessionAnalysis {
  const SessionAnalysis({
    this.summary,
    this.feedback,
    this.micText,
    this.speakers = const <SpeakerTurn>[],
  });

  final String? summary;
  final EnglishFeedbackEntity? feedback;

  /// Transcription propre du micro (MOI), null si pas encore traitée.
  final String? micText;

  /// Tours de parole diarizés du meeting.
  final List<SpeakerTurn> speakers;

  bool get isEmpty =>
      summary == null &&
      feedback == null &&
      micText == null &&
      speakers.isEmpty;

  SessionAnalysis copyWith({
    String? summary,
    EnglishFeedbackEntity? feedback,
    String? micText,
    List<SpeakerTurn>? speakers,
    bool clearSummary = false,
    bool clearFeedback = false,
  }) {
    return SessionAnalysis(
      summary: clearSummary ? null : (summary ?? this.summary),
      feedback: clearFeedback ? null : (feedback ?? this.feedback),
      micText: micText ?? this.micText,
      speakers: speakers ?? this.speakers,
    );
  }

  factory SessionAnalysis.fromStored(String? stored) {
    if (stored == null || stored.isEmpty) {
      return const SessionAnalysis();
    }
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is Map<String, dynamic>) {
        // Nouveau format enveloppe.
        if (decoded.containsKey('summary') ||
            decoded.containsKey('feedback') ||
            decoded.containsKey('micText') ||
            decoded.containsKey('speakers')) {
          final Object? fb = decoded['feedback'];
          final Object? sp = decoded['speakers'];
          return SessionAnalysis(
            summary: decoded['summary'] as String?,
            feedback: fb is Map<String, dynamic>
                ? EnglishFeedbackEntity.fromJson(fb)
                : null,
            micText: decoded['micText'] as String?,
            speakers: sp is List
                ? sp
                    .whereType<Map<String, dynamic>>()
                    .map(SpeakerTurn.fromJson)
                    .toList()
                : const <SpeakerTurn>[],
          );
        }
        // Ancien format : JSON coach brut.
        if (decoded.containsKey('corrections') ||
            decoded.containsKey('overall')) {
          return SessionAnalysis(
            feedback: EnglishFeedbackEntity.fromJson(decoded),
          );
        }
      }
    } catch (_) {
      // Pas du JSON : ancien résumé texte libre.
    }
    return SessionAnalysis(summary: stored);
  }

  String toStored() {
    return jsonEncode(<String, dynamic>{
      'summary': summary,
      'feedback': feedback?.toJson(),
      'micText': micText,
      'speakers': speakers.map((SpeakerTurn t) => t.toJson()).toList(),
    });
  }
}
