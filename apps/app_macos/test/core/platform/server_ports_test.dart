import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/server_ports.dart';

/// Un build de dev tourne à côté de l'app installée : il ne doit pas se
/// battre pour ses ports. La release garde les ports d'aujourd'hui (8000,
/// 8001) ; un lancement sur données de dev (debug, profile, OATS_DATA_DIR)
/// prend des ports fixes à lui. Ollama reste sur 11434 partout : un seul
/// démon, partagé (un modèle en mémoire unifiée, un seul écrivain du dossier
/// des modèles, qui est le dossier d'outils partagé).
///
/// Chaque URL cliente (WebSocket, /health, diarization) dérive des mêmes
/// ports : elles ne peuvent pas diverger du port donné au serveur.
///
/// Fonction pure : environnement et mode de build injectés, aucun port ouvert.
void main() {
  const Map<String, String> launched = <String, String>{
    'HOME': '/Users/someone',
  };
  const Map<String, String> withOverride = <String, String>{
    'HOME': '/Users/someone',
    'OATS_DATA_DIR': '/Volumes/scratch/oats-data',
  };

  ServerPorts ports(Map<String, String> env, AppBuildMode mode) =>
      resolveServerPorts(env, buildMode: mode);

  group('release : les ports d\'aujourd\'hui', () {
    final ServerPorts release = ports(launched, AppBuildMode.release);

    test('transcription sur 8000', () {
      expect(release.transcription, 8000);
    });

    test('diarization en direct sur 8001', () {
      expect(release.diarization, 8001);
    });

    test('Ollama sur 11434', () {
      expect(release.ollama, 11434);
    });
  });

  for (final (String name, Map<String, String> env, AppBuildMode mode)
      in <(String, Map<String, String>, AppBuildMode)>[
        ('debug', launched, AppBuildMode.debug),
        ('profile', launched, AppBuildMode.profile),
        ('release avec OATS_DATA_DIR', withOverride, AppBuildMode.release),
      ]) {
    group('$name : ports de dev, distincts de ceux de l\'app installée', () {
      final ServerPorts dev = ports(env, mode);

      test('transcription sur 8100', () {
        expect(dev.transcription, 8100);
      });

      test('diarization en direct sur 8101', () {
        expect(dev.diarization, 8101);
      });

      test('Ollama partagé : toujours 11434', () {
        expect(dev.ollama, 11434);
      });
    });
  }

  test('les ports de dev suivent usesDevDataDirectory, rien d\'autre', () {
    for (final AppBuildMode mode in AppBuildMode.values) {
      for (final Map<String, String> env in <Map<String, String>>[
        launched,
        withOverride,
      ]) {
        final bool dev = usesDevDataDirectory(env, buildMode: mode);
        expect(
          ports(env, mode).transcription,
          dev ? 8100 : 8000,
          reason: '${mode.name} $env',
        );
      }
    }
  });

  test('dans un même lancement, trois ports distincts', () {
    for (final AppBuildMode mode in AppBuildMode.values) {
      final ServerPorts p = ports(launched, mode);
      expect(<int>{p.transcription, p.diarization, p.ollama}, hasLength(3));
    }
  });

  group('les URL clientes dérivent des mêmes ports', () {
    test('release', () {
      final ServerPorts p = ports(launched, AppBuildMode.release);
      expect(
        p.transcriptionWebSocket,
        Uri.parse('ws://127.0.0.1:8000/v1/realtime'),
      );
      expect(p.transcriptionHealth, Uri.parse('http://127.0.0.1:8000/health'));
      expect(
        p.diarizationWebSocket,
        Uri.parse('ws://127.0.0.1:8001/v1/diarize'),
      );
      expect(p.diarizationHealth, Uri.parse('http://127.0.0.1:8001/health'));
      expect(p.ollamaBase.port, 11434);
    });

    test('dev', () {
      final ServerPorts p = ports(launched, AppBuildMode.debug);
      expect(
        p.transcriptionWebSocket,
        Uri.parse('ws://127.0.0.1:8100/v1/realtime'),
      );
      expect(p.transcriptionHealth, Uri.parse('http://127.0.0.1:8100/health'));
      expect(
        p.diarizationWebSocket,
        Uri.parse('ws://127.0.0.1:8101/v1/diarize'),
      );
      expect(p.diarizationHealth, Uri.parse('http://127.0.0.1:8101/health'));
      expect(p.ollamaBase.port, 11434);
    });
  });
}
