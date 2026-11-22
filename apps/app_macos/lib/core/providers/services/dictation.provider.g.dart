// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictation.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [GlobalShortcutChannel].

@ProviderFor(globalShortcutChannel)
const globalShortcutChannelProvider = GlobalShortcutChannelProvider._();

/// Provider singleton pour [GlobalShortcutChannel].

final class GlobalShortcutChannelProvider
    extends
        $FunctionalProvider<
          GlobalShortcutChannel,
          GlobalShortcutChannel,
          GlobalShortcutChannel
        >
    with $Provider<GlobalShortcutChannel> {
  /// Provider singleton pour [GlobalShortcutChannel].
  const GlobalShortcutChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalShortcutChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalShortcutChannelHash();

  @$internal
  @override
  $ProviderElement<GlobalShortcutChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GlobalShortcutChannel create(Ref ref) {
    return globalShortcutChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GlobalShortcutChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GlobalShortcutChannel>(value),
    );
  }
}

String _$globalShortcutChannelHash() =>
    r'0b005a42046e42d5f54cd5b194e95a7fd789c42f';

/// Provider singleton pour [TextOutputChannel].

@ProviderFor(textOutputChannel)
const textOutputChannelProvider = TextOutputChannelProvider._();

/// Provider singleton pour [TextOutputChannel].

final class TextOutputChannelProvider
    extends
        $FunctionalProvider<
          TextOutputChannel,
          TextOutputChannel,
          TextOutputChannel
        >
    with $Provider<TextOutputChannel> {
  /// Provider singleton pour [TextOutputChannel].
  const TextOutputChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'textOutputChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$textOutputChannelHash();

  @$internal
  @override
  $ProviderElement<TextOutputChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TextOutputChannel create(Ref ref) {
    return textOutputChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TextOutputChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TextOutputChannel>(value),
    );
  }
}

String _$textOutputChannelHash() => r'd353bc61455d00966f62543e81a13e6a55decfb4';

/// Derniers réglages de dictée enregistrés (Réglages, lancement) ; le
/// contrôleur les applique dès qu'ils changent.

@ProviderFor(DictationSettingsApplied)
const dictationSettingsAppliedProvider = DictationSettingsAppliedProvider._();

/// Derniers réglages de dictée enregistrés (Réglages, lancement) ; le
/// contrôleur les applique dès qu'ils changent.
final class DictationSettingsAppliedProvider
    extends $NotifierProvider<DictationSettingsApplied, DictationSettings?> {
  /// Derniers réglages de dictée enregistrés (Réglages, lancement) ; le
  /// contrôleur les applique dès qu'ils changent.
  const DictationSettingsAppliedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dictationSettingsAppliedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationSettingsAppliedHash();

  @$internal
  @override
  DictationSettingsApplied create() => DictationSettingsApplied();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DictationSettings? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DictationSettings?>(value),
    );
  }
}

String _$dictationSettingsAppliedHash() =>
    r'6c955dd15f055dcf1a7318fa0bd7efb495f1e5d3';

/// Derniers réglages de dictée enregistrés (Réglages, lancement) ; le
/// contrôleur les applique dès qu'ils changent.

abstract class _$DictationSettingsApplied
    extends $Notifier<DictationSettings?> {
  DictationSettings? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<DictationSettings?, DictationSettings?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DictationSettings?, DictationSettings?>,
              DictationSettings?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// La dictée : raccourci global, flux propre hors réunion (micro seul, sur
/// le serveur partagé), micro de la réunion pendant un enregistrement.

@ProviderFor(dictationController)
const dictationControllerProvider = DictationControllerProvider._();

/// La dictée : raccourci global, flux propre hors réunion (micro seul, sur
/// le serveur partagé), micro de la réunion pendant un enregistrement.

final class DictationControllerProvider
    extends
        $FunctionalProvider<
          DictationController,
          DictationController,
          DictationController
        >
    with $Provider<DictationController> {
  /// La dictée : raccourci global, flux propre hors réunion (micro seul, sur
  /// le serveur partagé), micro de la réunion pendant un enregistrement.
  const DictationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dictationControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationControllerHash();

  @$internal
  @override
  $ProviderElement<DictationController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DictationController create(Ref ref) {
    return dictationController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DictationController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DictationController>(value),
    );
  }
}

String _$dictationControllerHash() =>
    r'873f7239f2c6bfbb7e10a3f3df8d36951d820fd1';

/// État du raccourci global (Réglages : raccourci déjà pris).

@ProviderFor(dictationShortcutStatus)
const dictationShortcutStatusProvider = DictationShortcutStatusProvider._();

/// État du raccourci global (Réglages : raccourci déjà pris).

final class DictationShortcutStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ShortcutStatus>,
          ShortcutStatus,
          Stream<ShortcutStatus>
        >
    with $FutureModifier<ShortcutStatus>, $StreamProvider<ShortcutStatus> {
  /// État du raccourci global (Réglages : raccourci déjà pris).
  const DictationShortcutStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dictationShortcutStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationShortcutStatusHash();

  @$internal
  @override
  $StreamProviderElement<ShortcutStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ShortcutStatus> create(Ref ref) {
    return dictationShortcutStatus(ref);
  }
}

String _$dictationShortcutStatusHash() =>
    r'38ea026782085f892974953656734b4ba8c04e2e';
