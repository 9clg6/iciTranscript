// Runs the real live-answer path (detectQuestions, buildLiveAnswerRequest,
// OllamaLlmProvider, parseAnswer) against a real local model.
// Not part of the suite: `fvm flutter test tool/live_answers_probe.dart`
// with, in the environment:
//   MODE=contract|cold|load|gate, OUT=<dir>,
//   OLLAMA=http://127.0.0.1:11517 (your own daemon; the app's 11434 is
//   refused), MODEL=mistral, CASES=tool/live_answers_probe_cases.json,
//   PASSES=3 (contract), COLD_RUNS=3 (cold), LOAD_RUNS=5 (load),
//   LOGS=<dir>:<dir> and ASR=<json> (gate).
// See tool/server_probe/README.md at the repository root.
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/live_answers/answer_parser.dart';
import 'package:ici_transcript/application/services/live_answers/answer_prompt.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart'
    show AnswerSource;
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart'
    show kMaxContextChars;
import 'package:ici_transcript/application/services/live_answers/question_gate.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

final Map<String, String> env = Platform.environment;
final Uri target = Uri.parse(env['OLLAMA'] ?? 'http://127.0.0.1:11517');
late Directory out;
final List<Map<String, Object?>> sentBodies = <Map<String, Object?>>[];

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// The provider always posts to [ollamaBaseUrl] (11434, the shared daemon).
/// Rewrite to [target]; refuse anything else.
Dio guardedDio() {
  final Dio dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        final Uri u = o.uri;
        if (target.port == ollamaPort ||
            u.port != ollamaBaseUrl.port ||
            u.host != ollamaBaseUrl.host) {
          return h.reject(DioException(requestOptions: o, error: 'refused $u'));
        }
        o.path = target.replace(path: u.path).toString();
        if (o.data case final Map<String, Object?> body) sentBodies.add(body);
        h.next(o);
      },
    ),
  );
  return dio;
}

TranscriptSegmentEntity segment(String text, AudioSource source, int ms) =>
    TranscriptSegmentEntity(
      id: 'p$ms',
      sessionId: 'probe',
      source: source,
      text: text,
      timestampMs: ms,
      createdAt: DateTime(2026),
    );

ContextLine line(String who, int ms, String text) => (
  source: who == 'user' ? AudioSource.input : AudioSource.output,
  speaker: who == 'user' ? null : 0,
  timestampMs: ms,
  text: text,
);

/// Mirrors LiveAnswersService._contextFor: newest first, until
/// [kMaxContextChars]; the question line is the newest.
List<ContextLine> window(List<ContextLine> all) {
  final List<ContextLine> kept = <ContextLine>[];
  int chars = 0;
  for (final ContextLine c in all.reversed) {
    chars += contextLine(c).length + 1;
    if (chars > kMaxContextChars) break;
    kept.add(c);
  }
  return kept.reversed.toList();
}

/// Shape flags computed independently of parseAnswer.
Map<String, Object?> shape(String raw) {
  final List<String> lines = raw
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  bool any(String p) => RegExp(p, multiLine: true).hasMatch(raw);
  return <String, Object?>{
    'lines': lines.length,
    'dash_bullets': lines
        .where((String l) => RegExp(r'^[-*•]\s').hasMatch(l))
        .length,
    'numbered': lines
        .where((String l) => RegExp(r'^\d+[.)]\s').hasMatch(l))
        .length,
    'header': any(r'^\s*#+\s'),
    'bold': raw.contains('**'),
    'preamble':
        lines.isNotEmpty &&
        (RegExp(
              r'^(voici|here is|here are|here.s|réponse|answer|suggested|suggestion)\b',
              caseSensitive: false,
            ).hasMatch(lines.first) ||
            lines.first.endsWith(':')),
    'no_answer_anywhere': raw.contains(kNoAnswerToken),
    'no_answer_with_more':
        raw.contains(kNoAnswerToken) &&
        raw.replaceAll(RegExp(r'[\s`*_"]'), '') != kNoAnswerToken,
    'cite_S': RegExp(r'\[S\d+\]').allMatches(raw).length,
    'cite_multi': any(r'\[S?\d+\s*,\s*S?\d+'),
    'cite_paren': any(r'\(S\d+\)'),
    'cite_bare_num': any(r'\[\d+\]'),
    'cite_other': any(r'(?<!\[)\bS\d+\b(?!\])') || any(r'\[Source'),
    'line_without_period': lines.any(
      (String l) => !RegExp(r'[.!?…»")\]]$').hasMatch(l),
    ),
  };
}

const Set<String> _fr = <String>{
  'le', 'la', 'les', 'des', 'est', 'une', 'pour', 'dans', 'pas', 'que', //
  'qui', 'sur', 'avec', 'du', 'au', 'sont', 'nous', 'vous', 'il', 'et',
};
const Set<String> _en = <String>{
  'the', 'is', 'are', 'of', 'to', 'and', 'for', 'with', 'in', 'on', //
  'we', 'you', 'it', 'that', 'not', 'was', 'be', 'has', 'have', 'a',
};

String lang(String text) {
  final List<String> w = text
      .toLowerCase()
      .split(RegExp(r"[^\p{L}]+", unicode: true))
      .where((String s) => s.isNotEmpty)
      .toList();
  final int f = w.where(_fr.contains).length;
  final int e = w.where(_en.contains).length;
  return f == e ? '?' : (f > e ? 'fr' : 'en');
}

String folded(String s) => fold(s).toLowerCase();

Future<Map<String, Object?>> runCase(
  OllamaLlmProvider provider,
  Map<String, dynamic> meeting,
  Map<String, dynamic> c, {
  required String label,
  required int pass,
}) async {
  final List<dynamic> lines = meeting['lines'] as List<dynamic>;
  final List<ContextLine> all = <ContextLine>[
    for (int i = 0; i < lines.length; i++)
      line(
        (lines[i] as List<dynamic>)[0] as String,
        i * 13000,
        (lines[i] as List<dynamic>)[1] as String,
      ),
  ];
  final int askedMs = lines.length * 13000;
  final String question = c['question'] as String;
  final ContextLine asked = line('other', askedMs, question);
  final List<DocumentExcerpt> excerpts = <DocumentExcerpt>[
    for (final dynamic e in c['excerpts'] as List<dynamic>)
      DocumentExcerpt(
        documentId: e['id'] as String,
        documentTitle: e['title'] as String,
        text: (e['text'] as String).length > kMaxExcerptChars
            ? (e['text'] as String).substring(0, kMaxExcerptChars)
            : e['text'] as String,
      ),
  ];
  final List<String> gate = detectQuestions(
    segment(question, AudioSource.output, askedMs),
  );
  final LlmChatRequest request = buildLiveAnswerRequest(
    question: question,
    asked: asked,
    context: window(<ContextLine>[...all, asked]),
    excerpts: excerpts,
  );
  final String id = '${c['id']}_${label}_$pass';
  File('${out.path}/prompts/$id.txt')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      'SYSTEM:\n${request.systemPrompt}\n\nUSER:\n${request.messages.single.content}\n',
    );

  final int t0 = nowMs();
  int? first;
  int? firstVisible;
  final StringBuffer raw = StringBuffer();
  String? error;
  try {
    await for (final String d in provider.streamChat(request)) {
      first ??= nowMs();
      raw.write(d);
      if (firstVisible == null && raw.toString().trim().isNotEmpty) {
        firstVisible = nowMs();
      }
    }
  } on Object catch (e) {
    error = '$e';
  }
  final int t1 = nowMs();
  final String text = raw.toString();
  File('${out.path}/outputs/$id.txt')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  final ParsedAnswer p = parseAnswer(text, excerpts);
  final List<String> expected = <String>[
    for (final dynamic e in (c['expected'] as List<dynamic>?) ?? <dynamic>[])
      e as String,
  ];
  final String answerText = p.text;
  return <String, Object?>{
    'id': c['id'],
    'kind': c['kind'],
    'lang_q': meeting['lang'],
    'label': label,
    'pass': pass,
    'gate': gate,
    'prompt_chars':
        request.systemPrompt.length + request.messages.single.content.length,
    'start_ms': t0,
    'ttft_ms': first == null ? null : first - t0,
    'ttft_visible_ms': firstVisible == null ? null : firstVisible - t0,
    'total_ms': t1 - t0,
    'error': error,
    'raw': text,
    'declined': p.declined,
    'headline': p.headline,
    'bullets': p.bullets,
    'truncated': p.truncated,
    'contract_ok':
        error == null &&
        (p.declined ||
            (p.headline.isNotEmpty && p.bullets.length <= kMaxBullets)),
    'sources': <String>[for (final AnswerSource s in p.sources) s.documentId],
    'expected_doc': c['expected_doc'],
    'cites_expected': c['expected_doc'] == null
        ? null
        : p.sources.any((AnswerSource s) => s.documentId == c['expected_doc']),
    'expected_found': expected.isEmpty
        ? null
        : expected.any((String e) => folded(answerText).contains(folded(e))),
    'lang_a': p.declined ? null : lang(answerText),
    'shape': shape(text),
  };
}

Future<void> unload(Dio dio, String model) async {
  // Same guard: only the probe daemon. keep_alive 0 = unload now.
  await dio.post<Object?>(
    '${ollamaBaseUrl.resolve('/api/generate')}',
    data: <String, Object?>{'model': model, 'keep_alive': 0},
  );
  await Future<void>.delayed(const Duration(seconds: 2));
}

void writeJsonl(String name, List<Map<String, Object?>> rows) {
  File(
    '${out.path}/$name',
  ).writeAsStringSync('${rows.map(jsonEncode).join('\n')}\n');
}

Map<String, Object?> gateOn(List<({String src, String text})> texts) {
  final Map<String, Object?> res = <String, Object?>{};
  for (final String src in <String>{for (final t in texts) t.src}) {
    final List<String> all = <String>[
      for (final t in texts)
        if (t.src == src && t.text.trim().isNotEmpty) t.text.trim(),
    ];
    final List<Map<String, Object?>> hits = <Map<String, Object?>>[
      for (final String t in all)
        if (detectQuestions(segment(t, AudioSource.output, 0))
            case final List<String> q when q.isNotEmpty)
          <String, Object?>{'text': t, 'questions': q},
    ];
    res[src] = <String, Object?>{
      'segments': all.length,
      'unique': all.toSet().length,
      'hits': hits.length,
      'unique_hits': <String>{
        for (final h in hits) h['text']! as String,
      }.toList(),
    };
  }
  return res;
}

void main() {
  test('live answers probe', () async {
    out = Directory(env['OUT']!)..createSync(recursive: true);
    final String mode = env['MODE'] ?? 'contract';
    final String model = env['MODEL'] ?? OllamaLlmProvider.defaultModel;

    if (mode == 'gate') {
      final List<({String src, String text})> texts =
          <({String src, String text})>[];
      for (final String dir
          in (env['LOGS'] ?? '').split(':').where((String d) => d.isNotEmpty)) {
        for (final FileSystemEntity f in Directory(dir).listSync()) {
          if (!f.path.endsWith('.jsonl')) continue;
          for (final String l in File(f.path).readAsLinesSync()) {
            if (l.trim().isEmpty) continue;
            final Map<String, dynamic> e =
                jsonDecode(l) as Map<String, dynamic>;
            // `done` (live_probe) and `raw_done` (service_probe) are the
            // server's final texts; `segment` events are growing partials.
            if ((e['ev'] == 'done' || e['ev'] == 'raw_done') &&
                e['text'] is String) {
              texts.add((src: e['src'] as String, text: e['text'] as String));
            }
          }
        }
      }
      final Map<String, Object?> res = <String, Object?>{'logs': gateOn(texts)};
      if (env['ASR'] case final String asrPath) {
        final List<dynamic> asr =
            jsonDecode(File(asrPath).readAsStringSync()) as List<dynamic>;
        res['spoken'] = <Map<String, Object?>>[
          for (final dynamic a in asr)
            <String, Object?>{
              'lang': a['lang'],
              'ref': a['ref'],
              'asr': a['asr'],
              'detected_ref': detectQuestions(
                segment(a['ref'] as String, AudioSource.output, 0),
              ).isNotEmpty,
              'detected_asr': detectQuestions(
                segment(a['asr'] as String, AudioSource.output, 0),
              ).isNotEmpty,
            },
        ];
      }
      File(
        '${out.path}/gate.json',
      ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(res));
      return;
    }

    final Map<String, dynamic> fixture =
        jsonDecode(
              File(
                env['CASES'] ?? 'tool/live_answers_probe_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final Map<String, Map<String, dynamic>> meetings =
        <String, Map<String, dynamic>>{
          for (final dynamic m in fixture['meetings'] as List<dynamic>)
            m['id'] as String: m as Map<String, dynamic>,
        };
    final List<Map<String, dynamic>> cases = <Map<String, dynamic>>[
      for (final dynamic c in fixture['cases'] as List<dynamic>)
        c as Map<String, dynamic>,
    ];
    final Dio dio = guardedDio();
    final OllamaLlmProvider provider = OllamaLlmProvider(
      dio: dio,
      model: model,
    );
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    Future<void> one(Map<String, dynamic> c, String label, int pass) async {
      final Map<String, Object?> r = await runCase(
        provider,
        meetings[c['meeting']]!,
        c,
        label: label,
        pass: pass,
      );
      rows.add(r);
      stdout.writeln(
        '${r['id']} $label#$pass ttft=${r['ttft_ms']} total=${r['total_ms']} '
        'declined=${r['declined']} ok=${r['contract_ok']} '
        'raw=${jsonEncode((r['raw']! as String).replaceAll('\n', ' | '))}',
      );
    }

    switch (mode) {
      case 'contract':
        final int passes = int.parse(env['PASSES'] ?? '3');
        for (int p = 0; p < passes; p++) {
          for (int i = 0; i < cases.length; i++) {
            // The very first request of a fresh daemon loads the model.
            await one(cases[i], p == 0 && i == 0 ? 'first' : 'warm', p);
          }
        }
      case 'cold':
        final int n = int.parse(env['COLD_RUNS'] ?? '3');
        for (int i = 0; i < n; i++) {
          await unload(dio, model);
          await one(cases[(i * 7) % cases.length], 'cold', i);
        }
      case 'load':
        final int n = int.parse(env['LOAD_RUNS'] ?? '5');
        for (int i = 0; i < n; i++) {
          await one(cases[(i * 5) % cases.length], 'load', i);
        }
    }
    writeJsonl('$mode.jsonl', rows);
    File('${out.path}/$mode.request_bodies.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(<Object?>[
        // One body is enough to show what is sent; options are identical.
        if (sentBodies.isNotEmpty) sentBodies.first,
        <String, Object?>{'bodies_sent': sentBodies.length},
      ]),
    );
  }, timeout: Timeout.none);
}
