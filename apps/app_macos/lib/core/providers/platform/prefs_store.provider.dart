import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prefs_store.provider.g.dart';

/// Provider singleton pour [PrefsStore] (prefs.json).
@Riverpod(keepAlive: true)
PrefsStore prefsStore(Ref ref) => PrefsStore();
