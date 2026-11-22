import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Intervalle du micro dicté pendant une réunion, en ms depuis le début de
/// la réunion (même repère que les WAV et les segments). Ces mots ne
/// reviennent dans la note par aucune passe faite plus tard sur le WAV.
final class DictatedInterval {
  /// Cree une instance de [DictatedInterval].
  const DictatedInterval({required this.startMs, required this.endMs});

  /// Début (inclus).
  final int startMs;

  /// Fin (exclue).
  final int endMs;
}

/// `<recordings>/<sessionId>_dictations.json`, à côté des WAV de la session
/// (part avec eux) : `[{"source": "input", "startMs": int, "endMs": int}]`.
/// Synchrone : quelques octets, et l'isolat sert de verrou.
final class DictatedIntervalsStore {
  /// Cree une instance de [DictatedIntervalsStore].
  const DictatedIntervalsStore(this.recordingsDirectory);

  /// Dossier des enregistrements.
  final String recordingsDirectory;

  File _file(String sessionId) =>
      File('$recordingsDirectory/${sessionId}_dictations.json');

  /// Ajoute [interval] à la session [sessionId] (écriture atomique).
  void add(String sessionId, DictatedInterval interval) {
    final List<DictatedInterval> all = <DictatedInterval>[
      ...read(sessionId),
      interval,
    ];
    final File file = _file(sessionId);
    file.parent.createSync(recursive: true);
    final File tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode(<Map<String, Object>>[
        for (final DictatedInterval i in all)
          <String, Object>{
            'source': 'input',
            'startMs': i.startMs,
            'endMs': i.endMs,
          },
      ]),
      flush: true,
    );
    tmp.renameSync(file.path);
  }

  /// Intervalles de [sessionId], dans l'ordre ; vide si absent ou abîmé.
  List<DictatedInterval> read(String sessionId) {
    try {
      final Object? json = jsonDecode(_file(sessionId).readAsStringSync());
      if (json is! List) return const <DictatedInterval>[];
      return <DictatedInterval>[
        for (final Object? e in json)
          if (e case {'startMs': final int s, 'endMs': final int end})
            DictatedInterval(startMs: s, endMs: end),
      ];
    } on Object {
      return const <DictatedInterval>[];
    }
  }
}

const int _wavHeaderBytes = 44;
const int _bytesPerMs = 32; // PCM16 mono 16 kHz

/// Copie de [wav] (PCM16 mono 16 kHz, en-tête de 44 octets) avec
/// [intervals] en silence ; en-tête, durée et heures inchangés.
Uint8List muteDictatedIntervals(
  Uint8List wav,
  List<DictatedInterval> intervals,
) {
  final Uint8List out = Uint8List.fromList(wav);
  for (final DictatedInterval i in intervals) {
    final int start = (_wavHeaderBytes + i.startMs * _bytesPerMs).clamp(
      _wavHeaderBytes,
      out.length,
    );
    final int end = (_wavHeaderBytes + i.endMs * _bytesPerMs).clamp(
      start,
      out.length,
    );
    out.fillRange(start, end, 0);
  }
  return out;
}

/// [start, end) sans les [intervals] : les morceaux restants, dans l'ordre.
List<(int, int)> subtractIntervals(
  int start,
  int end,
  List<DictatedInterval> intervals,
) {
  List<(int, int)> parts = <(int, int)>[(start, end)];
  for (final DictatedInterval i in intervals) {
    parts = <(int, int)>[
      for (final (int s, int e) in parts) ...<(int, int)>[
        if (i.startMs > s) (s, i.startMs < e ? i.startMs : e),
        if (i.endMs < e) (i.endMs > s ? i.endMs : s, e),
      ],
    ].where(((int, int) p) => p.$2 > p.$1).toList();
  }
  return parts;
}
