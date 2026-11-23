// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coach_overview.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Lu à l'ouverture de la page, dans `summaries.content` (pas de
/// migration). Une erreur de lecture se relance à la main (Réessayer).

@ProviderFor(coachOverview)
const coachOverviewProvider = CoachOverviewProvider._();

/// Lu à l'ouverture de la page, dans `summaries.content` (pas de
/// migration). Une erreur de lecture se relance à la main (Réessayer).

final class CoachOverviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<CoachOverview>,
          CoachOverview,
          FutureOr<CoachOverview>
        >
    with $FutureModifier<CoachOverview>, $FutureProvider<CoachOverview> {
  /// Lu à l'ouverture de la page, dans `summaries.content` (pas de
  /// migration). Une erreur de lecture se relance à la main (Réessayer).
  const CoachOverviewProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'coachOverviewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coachOverviewHash();

  @$internal
  @override
  $FutureProviderElement<CoachOverview> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CoachOverview> create(Ref ref) {
    return coachOverview(ref);
  }
}

String _$coachOverviewHash() => r'8c6076747f4910fa15713a1418deb5314662efe9';
