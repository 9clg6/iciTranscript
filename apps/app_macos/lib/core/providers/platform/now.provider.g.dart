// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'now.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Horloge de l'agenda et de la détection de réunion (remplacée dans les
/// tests).

@ProviderFor(now)
const nowProvider = NowProvider._();

/// Horloge de l'agenda et de la détection de réunion (remplacée dans les
/// tests).

final class NowProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// Horloge de l'agenda et de la détection de réunion (remplacée dans les
  /// tests).
  const NowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nowProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nowHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return now(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$nowHash() => r'a18fd0a1c525818279254bbe775974fc6f13cf60';
