// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_history.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [SessionHistoryService].
///
/// Orchestre l'historique des sessions : chargement de la liste,
/// detail d'une session, suppression, modification du titre.

@ProviderFor(sessionHistoryService)
const sessionHistoryServiceProvider = SessionHistoryServiceProvider._();

/// Provider pour [SessionHistoryService].
///
/// Orchestre l'historique des sessions : chargement de la liste,
/// detail d'une session, suppression, modification du titre.

final class SessionHistoryServiceProvider
    extends
        $FunctionalProvider<
          SessionHistoryService,
          SessionHistoryService,
          SessionHistoryService
        >
    with $Provider<SessionHistoryService> {
  /// Provider pour [SessionHistoryService].
  ///
  /// Orchestre l'historique des sessions : chargement de la liste,
  /// detail d'une session, suppression, modification du titre.
  const SessionHistoryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionHistoryServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHistoryServiceHash();

  @$internal
  @override
  $ProviderElement<SessionHistoryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SessionHistoryService create(Ref ref) {
    return sessionHistoryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionHistoryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionHistoryService>(value),
    );
  }
}

String _$sessionHistoryServiceHash() =>
    r'c53afc860b151b9b19b722e4717b6153c3f4b493';
