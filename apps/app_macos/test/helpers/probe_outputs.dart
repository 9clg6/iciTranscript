import 'dart:convert';
import 'dart:io';

import 'package:ici_transcript/application/services/documents/document_library.dart';

/// Une sortie réelle enregistrée par la sonde (mistral 7B en local, contenu
/// de réunion inventé) : la question posée, les extraits fournis au modèle
/// (`[S1]`… dans l'ordre), et le texte brut rendu.
final class ProbeOutput {
  const ProbeOutput({
    required this.key,
    required this.kind,
    required this.lang,
    required this.question,
    required this.excerpts,
    required this.raw,
  });

  /// « run/id#passe », ex. `contract/en3-a#1`.
  final String key;

  /// a : réponse dans les documents ; b : dans la réunion ; c : nulle part ;
  /// d : pas une question pour l'utilisateur.
  final String kind;

  /// Langue de la question (fr, en).
  final String lang;
  final String question;
  final List<DocumentExcerpt> excerpts;
  final String raw;
}

Map<String, ProbeOutput>? _cache;

/// test/fixtures/live_answers/mistral_probe_outputs.json (cwd du package).
Map<String, ProbeOutput> probeOutputs() => _cache ??= <String, ProbeOutput>{
  for (final dynamic o
      in (jsonDecode(
                File(
                  'test/fixtures/live_answers/mistral_probe_outputs.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['outputs']
          as List<dynamic>)
    (o as Map<String, dynamic>)['key'] as String: ProbeOutput(
      key: o['key'] as String,
      kind: o['kind'] as String,
      lang: o['lang'] as String,
      question: o['question'] as String,
      excerpts: <DocumentExcerpt>[
        for (final dynamic e in o['excerpts'] as List<dynamic>)
          DocumentExcerpt(
            documentId: (e as Map<String, dynamic>)['documentId'] as String,
            documentTitle: e['documentTitle'] as String,
            text: e['text'] as String,
          ),
      ],
      raw: o['raw'] as String,
    ),
};

/// La sortie enregistrée [key] ; échoue si elle n'existe pas.
ProbeOutput probe(String key) {
  final ProbeOutput? o = probeOutputs()[key];
  if (o == null) throw ArgumentError('sortie enregistrée inconnue : $key');
  return o;
}
