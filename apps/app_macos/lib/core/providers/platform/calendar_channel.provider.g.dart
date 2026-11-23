// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_channel.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Agenda macOS (remplacé par un faux canal dans les tests).

@ProviderFor(calendarChannel)
const calendarChannelProvider = CalendarChannelProvider._();

/// Agenda macOS (remplacé par un faux canal dans les tests).

final class CalendarChannelProvider
    extends
        $FunctionalProvider<CalendarChannel, CalendarChannel, CalendarChannel>
    with $Provider<CalendarChannel> {
  /// Agenda macOS (remplacé par un faux canal dans les tests).
  const CalendarChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'calendarChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$calendarChannelHash();

  @$internal
  @override
  $ProviderElement<CalendarChannel> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CalendarChannel create(Ref ref) {
    return calendarChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CalendarChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CalendarChannel>(value),
    );
  }
}

String _$calendarChannelHash() => r'c7dd8e9382e314eb90502932754c3b65f30dd6a8';
