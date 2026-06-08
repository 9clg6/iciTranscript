// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_list.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel de la liste des sessions (sidebar).
///
/// Ecoute le [SessionHistoryService] pour charger et filtrer
/// les sessions, gerer la selection et la suppression.

@ProviderFor(SessionListViewModel)
const sessionListViewModelProvider = SessionListViewModelProvider._();

/// ViewModel de la liste des sessions (sidebar).
///
/// Ecoute le [SessionHistoryService] pour charger et filtrer
/// les sessions, gerer la selection et la suppression.
final class SessionListViewModelProvider
    extends $NotifierProvider<SessionListViewModel, SessionListState> {
  /// ViewModel de la liste des sessions (sidebar).
  ///
  /// Ecoute le [SessionHistoryService] pour charger et filtrer
  /// les sessions, gerer la selection et la suppression.
  const SessionListViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionListViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionListViewModelHash();

  @$internal
  @override
  SessionListViewModel create() => SessionListViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionListState>(value),
    );
  }
}

String _$sessionListViewModelHash() =>
    r'b019459d8b0d9554e3b5495a61937a988601b5f3';

/// ViewModel de la liste des sessions (sidebar).
///
/// Ecoute le [SessionHistoryService] pour charger et filtrer
/// les sessions, gerer la selection et la suppression.

abstract class _$SessionListViewModel extends $Notifier<SessionListState> {
  SessionListState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<SessionListState, SessionListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SessionListState, SessionListState>,
              SessionListState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
