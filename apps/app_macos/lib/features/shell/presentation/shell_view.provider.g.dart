// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_view.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Page courante du shell ; une note ouverte passe par-dessus
/// (`SessionListState.selectedSessionId`).

@ProviderFor(ShellViewController)
const shellViewControllerProvider = ShellViewControllerProvider._();

/// Page courante du shell ; une note ouverte passe par-dessus
/// (`SessionListState.selectedSessionId`).
final class ShellViewControllerProvider
    extends $NotifierProvider<ShellViewController, ShellView> {
  /// Page courante du shell ; une note ouverte passe par-dessus
  /// (`SessionListState.selectedSessionId`).
  const ShellViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellViewControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellViewControllerHash();

  @$internal
  @override
  ShellViewController create() => ShellViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellView>(value),
    );
  }
}

String _$shellViewControllerHash() =>
    r'48c326e537d944f2d6d7e5c59151b4f83ea35e66';

/// Page courante du shell ; une note ouverte passe par-dessus
/// (`SessionListState.selectedSessionId`).

abstract class _$ShellViewController extends $Notifier<ShellView> {
  ShellView build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ShellView, ShellView>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShellView, ShellView>,
              ShellView,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
