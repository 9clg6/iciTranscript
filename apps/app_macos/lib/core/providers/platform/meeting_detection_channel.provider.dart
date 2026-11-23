import 'package:ici_transcript/core/platform/meeting_detection_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'meeting_detection_channel.provider.g.dart';

/// Surveillance du micro (remplacée par un faux canal dans les tests).
@Riverpod(keepAlive: true)
MeetingDetectionChannel meetingDetectionChannel(Ref ref) =>
    const MeetingDetectionChannel();
