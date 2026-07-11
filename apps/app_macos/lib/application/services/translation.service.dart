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
  String get _diarDir =>
      '$_home/Library/Application Support/IciTranscript/diar';
  String get _scriptPath => '$_diarDir/translate_server.py';
  String get _uvBin => '$_home/.local/bin/uv';

  Process? _proc;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _processGeneration = 0;
  int _nextId = 0;
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  Completer<void>? _starting;
  Completer<void>? _ready;

  /// Démarre le processus de traduction (idempotent).
  Future<void> _ensureStarted() {
    final Completer<void>? starting = _starting;
    if (starting != null) return starting.future;
    if (_proc != null) return Future<void>.value();

    final Completer<void> nextStart = Completer<void>();
    _starting = nextStart;
    final int generation = ++_processGeneration;
    unawaited(_startProcess(nextStart, generation));
    return nextStart.future;
  }

  Future<void> _startProcess(Completer<void> starting, int generation) async {
    final Completer<void> ready = Completer<void>();
    _ready = ready;
    Process? process;
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;
    try {
      await _writeScript();
      process = await Process.start(
        _uvBin,
        <String>[
          'run',
          '--python',
          '3.12',
          '--with',
          'argostranslate',
          '--with',
          'certifi',
          'python',
          _scriptPath,
        ],
        environment: <String, String>{
          'HOME': _home,
          'PATH':
              '$_home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
        },
      );
      if (generation != _processGeneration) {
        process.kill();
        throw StateError('Démarrage traduction annulé');
      }

      _proc = process;
      stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) => _onLine(line, generation));
      stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String l) => _log.debug('[translate-err] $l'));
      _stdoutSub = stdoutSub;
      _stderrSub = stderrSub;
      unawaited(
        process.exitCode.then((int code) {
          if (generation != _processGeneration || !identical(_proc, process)) {
            return;
          }
          _log.warning('Processus traduction terminé ($code)');
          _proc = null;
          _stdoutSub = null;
          _stderrSub = null;
          final Completer<void>? currentReady = _ready;
          if (currentReady != null && !currentReady.isCompleted) {
            currentReady.completeError(
              StateError('Processus traduction terminé ($code)'),
            );
          }
          for (final Completer<String> c in _pending.values) {
            if (!c.isCompleted) c.complete('');
          }
          _pending.clear();
        }),
      );
      await ready.future.timeout(const Duration(seconds: 60));
      if (generation != _processGeneration || !identical(_proc, process)) {
        throw StateError('Démarrage traduction annulé');
      }
      if (!starting.isCompleted) starting.complete();
    } catch (e, stackTrace) {
      _log.error('Démarrage traduction échoué: $e');
      process?.kill();
      await stdoutSub?.cancel();
      await stderrSub?.cancel();
      if (generation == _processGeneration) {
        _processGeneration++;
        if (identical(_proc, process)) _proc = null;
        if (identical(_stdoutSub, stdoutSub)) _stdoutSub = null;
        if (identical(_stderrSub, stderrSub)) _stderrSub = null;
        if (identical(_ready, ready)) _ready = null;
      }
      if (!starting.isCompleted) starting.completeError(e, stackTrace);
    } finally {
      if (identical(_starting, starting)) _starting = null;
    }
  }

  void _onLine(String line, int generation) {
    if (generation != _processGeneration) return;
    if (line.trim().isEmpty) return;
    try {
      final Map<String, dynamic> j = jsonDecode(line) as Map<String, dynamic>;
      if (j['type'] == 'ready') {
        final Completer<void>? ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
        return;
      }
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
    return _request(text: text, from: from, to: to);
  }

  /// Charge le runtime et installe la route de langues avant le premier delta.
  Future<bool> preparePair({required String from, required String to}) async {
    if (from == to) return true;
    final String result = await _request(
      text: '',
      from: from,
      to: to,
      prepareOnly: true,
    );
    return result == '__ready__';
  }

  Future<String> _request({
    required String text,
    required String from,
    required String to,
    bool prepareOnly = false,
  }) async {
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
    try {
      proc.stdin.writeln(
        jsonEncode(<String, dynamic>{
          'id': id,
          'from': from,
          'to': to,
          'text': text,
          'prepare': prepareOnly,
        }),
      );
      // Sans flush, la ligne peut rester bufferisée côté Dart.
      await proc.stdin.flush();
    } catch (e) {
      _pending.remove(id);
      _log.warning('Envoi traduction échoué: $e');
      return '';
    }

    return completer.future.timeout(
      // Large : le 1er appel d'une paire télécharge le modèle de langue.
      const Duration(seconds: 120),
      onTimeout: () {
        _pending.remove(id);
        return '';
      },
    );
  }

  Future<void> dispose() async {
    _processGeneration++;
    final Process? process = _proc;
    _proc = null;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    process?.kill();
    for (final Completer<String> completer in _pending.values) {
      if (!completer.isCompleted) completer.complete('');
    }
    _pending.clear();
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

def has_pair(frm, to):
    langs = {x.code: x for x in tr.get_installed_languages()}
    if frm not in langs or to not in langs:
        return False
    try:
        langs[frm].get_translation(langs[to])
        return True
    except Exception:
        return False

def ensure(frm, to):
    if (frm, to) in installed:
        return
    if not has_pair(frm, to):
        pk.update_package_index()
        av = pk.get_available_packages()
        p = next((x for x in av if x.from_code == frm and x.to_code == to), None)
        if not p:
            raise RuntimeError(f"No Argos package for {frm}->{to}")
        pk.install_from_path(p.download())
    if not has_pair(frm, to):
        raise RuntimeError(f"Argos package unavailable after install: {frm}->{to}")
    installed.add((frm, to))

def ensure_route(frm, to):
    if has_pair(frm, to):
        ensure(frm, to)
        return
    if frm == "en" or to == "en":
        ensure(frm, to)
        return
    ensure(frm, "en")
    ensure("en", to)

def translate_text(text, frm, to):
    if has_pair(frm, to):
        return tr.translate(text, frm, to)
    via_english = tr.translate(text, frm, "en")
    return tr.translate(via_english, "en", to)

print(json.dumps({"type": "ready"}), flush=True)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    rid = -1
    try:
        req = json.loads(line)
        rid = req.get("id", -1)
        ensure_route(req["from"], req["to"])
        out = "__ready__" if req.get("prepare") else translate_text(
            req["text"], req["from"], req["to"])
        print(json.dumps({"id": rid, "text": out}), flush=True)
    except Exception as e:
        print(json.dumps({"id": rid, "text": "", "error": str(e)}), flush=True)
''';
}
