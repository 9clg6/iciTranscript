// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meeting_detection_channel.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Surveillance du micro (remplacée par un faux canal dans les tests).

@ProviderFor(meetingDetectionChannel)
const meetingDetectionChannelProvider = MeetingDetectionChannelProvider._();

/// Surveillance du micro (remplacée par un faux canal dans les tests).

final class MeetingDetectionChannelProvider
    extends
        $FunctionalProvider<
          MeetingDetectionChannel,
          MeetingDetectionChannel,
          MeetingDetectionChannel
        >
    with $Provider<MeetingDetectionChannel> {
  /// Surveillance du micro (remplacée par un faux canal dans les tests).
  const MeetingDetectionChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'meetingDetectionChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$meetingDetectionChannelHash();

  @$internal
  @override
  $ProviderElement<MeetingDetectionChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MeetingDetectionChannel create(Ref ref) {
    return meetingDetectionChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MeetingDetectionChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MeetingDetectionChannel>(value),
    );
  }
}

String _$meetingDetectionChannelHash() =>
    r'84305d47c61a518c9d24c36bea89bca33732b8e0';
