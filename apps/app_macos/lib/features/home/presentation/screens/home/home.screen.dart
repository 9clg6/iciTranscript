import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/home/presentation/agenda.dart';
import 'package:ici_transcript/features/home/presentation/widgets/upcoming_events.widget.dart';
import 'package:ici_transcript/features/shell/presentation/start_note.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Largeur de lecture de la colonne de contenu.
const double kContentMaxWidth = 760;

/// Accueil « agenda » : à venir, puis l'historique groupé par jour.
class HomeScreen extends ConsumerStatefulWidget {
  /// Crée l'accueil.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // La requête vit dans le view model (gardé en vie par le shell) : le champ
  // repart d'elle pour ne jamais afficher autre chose que le filtre appliqué.
  late final TextEditingController _search = TextEditingController(
    text: ref.read(sessionListViewModelProvider).searchQuery,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Démarre une note ; si une note est déjà en cours, y retourne.
  Future<void> _newNote() => startOrShowNote(ref.read);

  @override
  Widget build(BuildContext context) {
    final SessionListState state = ref.watch(sessionListViewModelProvider);
    final SessionListViewModel vm = ref.read(
      sessionListViewModelProvider.notifier,
    );
    final List<AgendaDay> days = groupSessionsByDay(
      filterSessionsByTitle(state.sessions, state.searchQuery),
    );
    final DateTime now = DateTime.now();
    final Oats o = context.oats;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.xxxl,
        vertical: OatsSpace.xl,
      ),
      children: <Widget>[
        _Column(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: OatsSearchField(
                      controller: _search,
                      hint: LocaleKeys.home_search.tr(),
                      onChanged: vm.search,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: OatsSpace.md),
              OatsPrimaryButton(
                icon: Icons.add,
                label: LocaleKeys.home_new_note.tr(),
                onPressed: _newNote,
              ),
            ],
          ),
        ),
        const SizedBox(height: OatsSpace.xxl),
        const _Column(child: UpcomingEventsBlock()),
        const SizedBox(height: OatsSpace.xxl),
        if (state.sessions.isEmpty)
          _Column(
            child: Padding(
              padding: const EdgeInsets.only(top: OatsSpace.xl),
              child: OatsEmptyState(
                icon: Icons.mic_none_outlined,
                message: LocaleKeys.home_empty.tr(),
              ),
            ),
          )
        else if (days.isEmpty)
          _Column(
            child: Padding(
              padding: const EdgeInsets.only(top: OatsSpace.xl),
              child: OatsEmptyState(
                icon: Icons.search_off_outlined,
                message: LocaleKeys.home_no_result.tr(
                  args: <String>[state.searchQuery.trim()],
                ),
              ),
            ),
          )
        else
          for (final AgendaDay day in days)
            _Column(
              child: Padding(
                padding: const EdgeInsets.only(bottom: OatsSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: OatsSpace.sm,
                        bottom: OatsSpace.xs,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          formatDayHeader(day.day, now: now),
                          style: o.label,
                        ),
                      ),
                    ),
                    for (final SessionEntity s in day.sessions)
                      OatsListRow(
                        title: s.title,
                        trailing: <String>[
                          formatStartTime(s.createdAt),
                          ?formatDuration(s.durationSeconds),
                        ].join(' · '),
                        onTap: () => vm.selectSession(s.id),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// Colonne centrée de largeur de lecture.
class _Column extends StatelessWidget {
  const _Column({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      child: child,
    ),
  );
}
