// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_prefs.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Lit et range [CalendarPrefs].

@ProviderFor(CalendarPrefsController)
const calendarPrefsControllerProvider = CalendarPrefsControllerProvider._();

/// Lit et range [CalendarPrefs].
final class CalendarPrefsControllerProvider
    extends $AsyncNotifierProvider<CalendarPrefsController, CalendarPrefs> {
  /// Lit et range [CalendarPrefs].
  const CalendarPrefsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'calendarPrefsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$calendarPrefsControllerHash();

  @$internal
  @override
  CalendarPrefsController create() => CalendarPrefsController();
}

String _$calendarPrefsControllerHash() =>
    r'57ec95168f36f27d65ea2d82e6e3c0ba47152806';

/// Lit et range [CalendarPrefs].

abstract class _$CalendarPrefsController extends $AsyncNotifier<CalendarPrefs> {
  FutureOr<CalendarPrefs> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<CalendarPrefs>, CalendarPrefs>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CalendarPrefs>, CalendarPrefs>,
              AsyncValue<CalendarPrefs>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
