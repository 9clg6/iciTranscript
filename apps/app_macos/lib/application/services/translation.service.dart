import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_foundation/logging/logger.dart';

/// Service de traduction par phrase, hors-ligne, via Argos Translate.
///
/// Lance un processus Python persistant (stdin/stdout JSON) pour une faible
/// latence. CPU-only → aucune contention GPU (pas de crash). Les paires de
/// langues sont téléchargées à la demande (1×) puis disponibles hors-ligne.
class TranslationService {
  TranslationService();

  final Log _log = Log.named('TranslationService');

  String get _home => Platform.environment['HOME'] ?? '/tmp';
  String get _diarDir => '$_home/Library/Application Support/IciTranscript/diar';
  String get _scriptPath => '$_diarDir/translate_server.py';
  String get _uvBin => '$_home/.local/bin/uv';

  Process? _proc;
  StreamSubscription<String>? _stdoutSub;
  int _nextId = 0;
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  Completer<void>? _starting;

  /// Démarre le processus de traduction (idempotent).
  Future<void> _ensureStarted() async {
    if (_proc != null) return;
    if (_starting != null) return _starting!.future;
    _starting = Completer<void>();
    try {
      await _writeScript();
      _proc = await Process.start(
        _uvBin,
        <String>[
          'run',
          '--python', '3.12',
          '--with', 'argostranslate',
          '--with', 'certifi',
          'python',
          _scriptPath,
        ],
        environment: <String, String>{
          'HOME': _home,
          'PATH': '$_home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
        },
      );
      _stdoutSub = _proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      _proc!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String l) => _log.debug('[translate-err] $l'));
      unawaited(_proc!.exitCode.then((int code) {
        _log.warning('Processus traduction terminé ($code)');
        _proc = null;
        for (final Completer<String> c in _pending.values) {
          if (!c.isCompleted) c.complete('');
        }
        _pending.clear();
      }));
      _starting!.complete();
    } catch (e) {
      _log.error('Démarrage traduction échoué: $e');
      _starting!.completeError(e);
      _starting = null;
      rethrow;
    }
    _starting = null;
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final Map<String, dynamic> j = jsonDecode(line) as Map<String, dynamic>;
      final int id = (j['id'] as num?)?.toInt() ?? -1;
      final Completer<String>? c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        c.complete(j['text'] as String? ?? '');
      }
    } catch (_) {
      // Ligne non-JSON (logs argos) — ignorer.
    }
  }

  /// Traduit [text] de [from] vers [to]. Renvoie '' en cas d'échec/timeout.
  Future<String> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    if (text.trim().isEmpty || from == to) return '';
    try {
      await _ensureStarted();
    } catch (_) {
      return '';
    }
    final Process? proc = _proc;
    if (proc == null) return '';

    final int id = _nextId++;
    final Completer<String> completer = Completer<String>();
    _pending[id] = completer;
    proc.stdin.writeln(jsonEncode(<String, dynamic>{
      'id': id,
      'from': from,
      'to': to,
      'text': text,
    }));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        return '';
      },
    );
  }

  Future<void> dispose() async {
    await _stdoutSub?.cancel();
    _proc?.kill();
    _proc = null;
  }

  Future<void> _writeScript() async {
    final File f = File(_scriptPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(_pyServer);
  }

  static const String _pyServer = r'''
import sys, json, os, ssl
try:
    import certifi
    os.environ["SSL_CERT_FILE"] = certifi.where()
    os.environ["REQUESTS_CA_BUNDLE"] = certifi.where()
    ssl._create_default_https_context = lambda *a, **k: ssl.create_default_context(cafile=certifi.where())
except Exception:
    pass
import argostranslate.package as pk
import argostranslate.translate as tr

installed = set()

def ensure(frm, to):
    if (frm, to) in installed:
        return
    try:
        pk.update_package_index()
        av = pk.get_available_packages()
        p = next((x for x in av if x.from_code == frm and x.to_code == to), None)
        if p:
            pk.install_from_path(p.download())
    except Exception:
        pass
    installed.add((frm, to))

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    rid = -1
    try:
        req = json.loads(line)
        rid = req.get("id", -1)
        ensure(req["from"], req["to"])
        out = tr.translate(req["text"], req["from"], req["to"])
        print(json.dumps({"id": rid, "text": out}), flush=True)
    except Exception as e:
        print(json.dumps({"id": rid, "text": "", "error": str(e)}), flush=True)
''';
}
