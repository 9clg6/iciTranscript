// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'summary.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [SummaryService].

@ProviderFor(summaryService)
const summaryServiceProvider = SummaryServiceProvider._();

/// Provider pour [SummaryService].

final class SummaryServiceProvider
    extends $FunctionalProvider<SummaryService, SummaryService, SummaryService>
    with $Provider<SummaryService> {
  /// Provider pour [SummaryService].
  const SummaryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'summaryServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$summaryServiceHash();

  @$internal
  @override
  $ProviderElement<SummaryService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SummaryService create(Ref ref) {
    return summaryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SummaryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SummaryService>(value),
    );
  }
}

String _$summaryServiceHash() => r'6767b0a00e39aa4c8c23148ee1e2c7c09c84e6f8';
