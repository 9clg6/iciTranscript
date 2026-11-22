import 'package:auto_route/auto_route.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/platform/dev_data_directory.provider.dart';
import 'package:ici_transcript/features/documents/presentation/documents.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.screen.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Largeur de la barre latérale.
const double kSidebarWidth = 220;

/// Shell d'Oats : barre latérale + page courante ; une note ouverte
/// remplace la page jusqu'au Retour.
@RoutePage()
class OatsShellScreen extends ConsumerWidget {
  /// Crée le shell.
  const OatsShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Oats o = context.oats;
    final ShellView view = ref.watch(shellViewControllerProvider);
    final String? openNote = ref.watch(
      sessionListViewModelProvider.select(
        (SessionListState s) => s.selectedSessionId,
      ),
    );
    final SessionListViewModel notes = ref.read(
      sessionListViewModelProvider.notifier,
    );

    final Widget page = openNote != null
        ? SessionDetailScreen(
            key: ValueKey<String>(openNote),
            sessionId: openNote,
            onClose: notes.clearSelection,
          )
        : switch (view) {
            ShellView.home => const HomeScreen(),
            ShellView.documents => const DocumentsScreen(),
            ShellView.coach => _EmptyPage(
              title: LocaleKeys.nav_coach.tr(),
              icon: Icons.school_outlined,
              emptyTitle: null,
              message: LocaleKeys.coach_empty.tr(),
            ),
            ShellView.settings => const SettingsScreen(),
            ShellView.live => const LiveTranscriptionScreen(),
          };

    return Scaffold(
      backgroundColor: o.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Sidebar(
            current: view,
            onSelect: (ShellView v) {
              notes.clearSelection();
              ref.read(shellViewControllerProvider.notifier).show(v);
            },
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final ShellView current;
  final ValueChanged<ShellView> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Oats o = context.oats;
    final bool devData = ref.watch(isDevDataDirectoryProvider);
    final bool recording = ref.watch(
      liveTranscriptionViewModelProvider.select(
        (LiveTranscriptionState s) => s.isRecording || s.isPaused,
      ),
    );

    Widget item(ShellView v, IconData icon, String key) => Padding(
      padding: const EdgeInsets.only(bottom: OatsSpace.xxs),
      child: OatsSidebarItem(
        icon: icon,
        label: key.tr(),
        selected: current == v,
        onTap: () => onSelect(v),
      ),
    );

    return Container(
      key: const ValueKey<String>('oats-sidebar'),
      width: kSidebarWidth,
      padding: const EdgeInsets.fromLTRB(
        OatsSpace.md,
        OatsSpace.lg,
        OatsSpace.md,
        OatsSpace.md,
      ),
      decoration: BoxDecoration(
        color: o.sidebar,
        border: Border(right: BorderSide(color: o.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OatsSpace.sm,
              0,
              OatsSpace.sm,
              OatsSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(LocaleKeys.app_name.tr(), style: o.wordmark),
                // Un lancement de dev n'ouvre pas les vraies notes : le dire.
                if (devData) Text(LocaleKeys.app_dev_data.tr(), style: o.label),
              ],
            ),
          ),
          item(ShellView.home, Icons.home_outlined, LocaleKeys.nav_home),
          item(
            ShellView.documents,
            Icons.description_outlined,
            LocaleKeys.nav_documents,
          ),
          item(ShellView.coach, Icons.school_outlined, LocaleKeys.nav_coach),
          if (recording) ...<Widget>[
            const SizedBox(height: OatsSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(OatsRadius.pill),
                onTap: () => onSelect(ShellView.live),
                child: OatsLivePill(label: LocaleKeys.nav_recording.tr()),
              ),
            ),
          ],
          const Spacer(),
          item(
            ShellView.settings,
            Icons.settings_outlined,
            LocaleKeys.nav_settings,
          ),
        ],
      ),
    );
  }
}

/// Page sans contenu encore : titre serif et état vide honnête.
class _EmptyPage extends StatelessWidget {
  const _EmptyPage({
    required this.title,
    required this.icon,
    required this.emptyTitle,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String? emptyTitle;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      OatsSpace.xxxl,
      OatsSpace.xl,
      OatsSpace.xxxl,
      OatsSpace.xl,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: OatsPageHeader(title: title),
          ),
        ),
        Expanded(
          child: OatsEmptyState(
            icon: icon,
            title: emptyTitle,
            message: message,
          ),
        ),
      ],
    ),
  );
}
