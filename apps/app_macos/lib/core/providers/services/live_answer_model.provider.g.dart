// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_answer_model.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Modèle qui répond aux questions en direct ; null = aucun modèle prêt
/// (envoi coupé et modèle local absent) : rien n'est envoyé. Relu à chaque
/// question.

@ProviderFor(liveAnswerModel)
const liveAnswerModelProvider = LiveAnswerModelProvider._();

/// Modèle qui répond aux questions en direct ; null = aucun modèle prêt
/// (envoi coupé et modèle local absent) : rien n'est envoyé. Relu à chaque
/// question.

final class LiveAnswerModelProvider
    extends
        $FunctionalProvider<
          AsyncValue<LiveAnswerModel?>,
          LiveAnswerModel?,
          FutureOr<LiveAnswerModel?>
        >
    with $FutureModifier<LiveAnswerModel?>, $FutureProvider<LiveAnswerModel?> {
  /// Modèle qui répond aux questions en direct ; null = aucun modèle prêt
  /// (envoi coupé et modèle local absent) : rien n'est envoyé. Relu à chaque
  /// question.
  const LiveAnswerModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveAnswerModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveAnswerModelHash();

  @$internal
  @override
  $FutureProviderElement<LiveAnswerModel?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LiveAnswerModel?> create(Ref ref) {
    return liveAnswerModel(ref);
  }
}

String _$liveAnswerModelHash() => r'c353e9d1e981d44237e90d9bae0d45dfa50b52a5';
