import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dictation.provider.g.dart';

/// Provider singleton pour [GlobalShortcutChannel].
@Riverpod(keepAlive: true)
GlobalShortcutChannel globalShortcutChannel(Ref ref) => GlobalShortcutChannel();

/// Provider singleton pour [TextOutputChannel].
@Riverpod(keepAlive: true)
TextOutputChannel textOutputChannel(Ref ref) => TextOutputChannel();
