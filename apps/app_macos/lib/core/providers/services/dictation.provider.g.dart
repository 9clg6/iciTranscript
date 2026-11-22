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
