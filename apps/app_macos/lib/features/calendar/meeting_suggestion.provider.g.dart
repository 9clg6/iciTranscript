// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meeting_suggestion.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Lance la surveillance du micro une fois ; false sous macOS 14 (seuls les
/// événements de l'agenda déclenchent alors une suggestion).
// ponytail: la surveillance tourne toute la vie de l'app, détection coupée
// ou non (quelques écouteurs Core Audio) ; les instantanés sont alors
// ignorés.

@ProviderFor(meetingDetectionSupported)
const meetingDetectionSupportedProvider = MeetingDetectionSupportedProvider._();

/// Lance la surveillance du micro une fois ; false sous macOS 14 (seuls les
/// événements de l'agenda déclenchent alors une suggestion).
// ponytail: la surveillance tourne toute la vie de l'app, détection coupée
// ou non (quelques écouteurs Core Audio) ; les instantanés sont alors
// ignorés.

final class MeetingDetectionSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Lance la surveillance du micro une fois ; false sous macOS 14 (seuls les
  /// événements de l'agenda déclenchent alors une suggestion).
  // ponytail: la surveillance tourne toute la vie de l'app, détection coupée
  // ou non (quelques écouteurs Core Audio) ; les instantanés sont alors
  // ignorés.
  const MeetingDetectionSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'meetingDetectionSupportedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$meetingDetectionSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return meetingDetectionSupported(ref);
  }
}

String _$meetingDetectionSupportedHash() =>
    r'cd94901d193ec59b8fbfb5d52d7dcf288908f98d';

/// Suggestion de démarrer une note affichée par le shell, ou null.

@ProviderFor(MeetingSuggestionController)
const meetingSuggestionControllerProvider =
    MeetingSuggestionControllerProvider._();

/// Suggestion de démarrer une note affichée par le shell, ou null.
final class MeetingSuggestionControllerProvider
    extends $NotifierProvider<MeetingSuggestionController, MeetingSuggestion?> {
  /// Suggestion de démarrer une note affichée par le shell, ou null.
  const MeetingSuggestionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'meetingSuggestionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$meetingSuggestionControllerHash();

  @$internal
  @override
  MeetingSuggestionController create() => MeetingSuggestionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MeetingSuggestion? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MeetingSuggestion?>(value),
    );
  }
}

String _$meetingSuggestionControllerHash() =>
    r'09c3a9f3c44763f9a7d236146eca546eb5bf01e7';

/// Suggestion de démarrer une note affichée par le shell, ou null.

abstract class _$MeetingSuggestionController
    extends $Notifier<MeetingSuggestion?> {
  MeetingSuggestion? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<MeetingSuggestion?, MeetingSuggestion?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MeetingSuggestion?, MeetingSuggestion?>,
              MeetingSuggestion?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
