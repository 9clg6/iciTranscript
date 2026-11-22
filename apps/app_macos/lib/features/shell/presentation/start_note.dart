import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';

/// Montre le direct et démarre une note ; si une note est déjà en cours, y
/// retourne sans en lancer une seconde. Le lien à l'agenda suit
/// `eventToLink` (dans `startSession`). [read] = `ref.read`.
Future<void> startOrShowNote(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  read(sessionListViewModelProvider.notifier).clearSelection();
  read(shellViewControllerProvider.notifier).show(ShellView.live);
  final LiveTranscriptionState live = read(liveTranscriptionViewModelProvider);
  if (live.isRecording || live.isPaused) return;
  await read(liveTranscriptionViewModelProvider.notifier).startSession();
}
