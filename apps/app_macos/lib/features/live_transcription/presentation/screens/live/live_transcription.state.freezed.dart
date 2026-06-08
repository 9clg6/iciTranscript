// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_transcription.state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveTranscriptionState {

/// Liste des segments de transcription de la session courante.
 List<TranscriptSegmentEntity> get segments;/// Indique si un enregistrement est en cours.
 bool get isRecording;/// Indique si l'enregistrement est en pause.
 bool get isPaused;/// Duree actuelle de la session.
 Duration get duration;/// Etat du serveur de transcription.
 ServerState get serverState;/// Titre de la session en cours.
 String? get sessionTitle;/// Statut de la permission microphone.
/// Valeurs : "authorized", "denied", "notDetermined", "restricted", "unknown".
 String get micPermission;/// Statut de la permission Screen Recording.
/// Valeurs : "authorized", "denied", "notDetermined", "unknown".
 String get screenRecordingPermission;/// Indique si l'option coach d'anglais est activée.
 bool get isCoachEnabled;/// Indique si la traduction temps réel est activée.
 bool get isTranslationEnabled;/// Langue source de la traduction (code ISO, ex: "en").
 String get translationFrom;/// Langue cible de la traduction (code ISO, ex: "fr").
 String get translationTo;/// Traductions par segment (id segment → texte traduit).
 Map<String, String> get translations;/// Retour du coach d'anglais (null si pas encore généré).
 EnglishFeedbackEntity? get feedback;/// Indique si l'analyse de l'anglais est en cours.
 bool get isFeedbackLoading;/// Étape courante du setup Ollama.
 OllamaSetupStage get ollamaSetupStage;/// Progression du setup Ollama (0.0 – 1.0).
 double get ollamaSetupProgress;/// Message d'erreur du setup Ollama.
 String? get ollamaSetupError;
/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveTranscriptionStateCopyWith<LiveTranscriptionState> get copyWith => _$LiveTranscriptionStateCopyWithImpl<LiveTranscriptionState>(this as LiveTranscriptionState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveTranscriptionState&&const DeepCollectionEquality().equals(other.segments, segments)&&(identical(other.isRecording, isRecording) || other.isRecording == isRecording)&&(identical(other.isPaused, isPaused) || other.isPaused == isPaused)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.serverState, serverState) || other.serverState == serverState)&&(identical(other.sessionTitle, sessionTitle) || other.sessionTitle == sessionTitle)&&(identical(other.micPermission, micPermission) || other.micPermission == micPermission)&&(identical(other.screenRecordingPermission, screenRecordingPermission) || other.screenRecordingPermission == screenRecordingPermission)&&(identical(other.isCoachEnabled, isCoachEnabled) || other.isCoachEnabled == isCoachEnabled)&&(identical(other.isTranslationEnabled, isTranslationEnabled) || other.isTranslationEnabled == isTranslationEnabled)&&(identical(other.translationFrom, translationFrom) || other.translationFrom == translationFrom)&&(identical(other.translationTo, translationTo) || other.translationTo == translationTo)&&const DeepCollectionEquality().equals(other.translations, translations)&&(identical(other.feedback, feedback) || other.feedback == feedback)&&(identical(other.isFeedbackLoading, isFeedbackLoading) || other.isFeedbackLoading == isFeedbackLoading)&&(identical(other.ollamaSetupStage, ollamaSetupStage) || other.ollamaSetupStage == ollamaSetupStage)&&(identical(other.ollamaSetupProgress, ollamaSetupProgress) || other.ollamaSetupProgress == ollamaSetupProgress)&&(identical(other.ollamaSetupError, ollamaSetupError) || other.ollamaSetupError == ollamaSetupError));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(segments),isRecording,isPaused,duration,serverState,sessionTitle,micPermission,screenRecordingPermission,isCoachEnabled,isTranslationEnabled,translationFrom,translationTo,const DeepCollectionEquality().hash(translations),feedback,isFeedbackLoading,ollamaSetupStage,ollamaSetupProgress,ollamaSetupError);

@override
String toString() {
  return 'LiveTranscriptionState(segments: $segments, isRecording: $isRecording, isPaused: $isPaused, duration: $duration, serverState: $serverState, sessionTitle: $sessionTitle, micPermission: $micPermission, screenRecordingPermission: $screenRecordingPermission, isCoachEnabled: $isCoachEnabled, isTranslationEnabled: $isTranslationEnabled, translationFrom: $translationFrom, translationTo: $translationTo, translations: $translations, feedback: $feedback, isFeedbackLoading: $isFeedbackLoading, ollamaSetupStage: $ollamaSetupStage, ollamaSetupProgress: $ollamaSetupProgress, ollamaSetupError: $ollamaSetupError)';
}


}

/// @nodoc
abstract mixin class $LiveTranscriptionStateCopyWith<$Res>  {
  factory $LiveTranscriptionStateCopyWith(LiveTranscriptionState value, $Res Function(LiveTranscriptionState) _then) = _$LiveTranscriptionStateCopyWithImpl;
@useResult
$Res call({
 List<TranscriptSegmentEntity> segments, bool isRecording, bool isPaused, Duration duration, ServerState serverState, String? sessionTitle, String micPermission, String screenRecordingPermission, bool isCoachEnabled, bool isTranslationEnabled, String translationFrom, String translationTo, Map<String, String> translations, EnglishFeedbackEntity? feedback, bool isFeedbackLoading, OllamaSetupStage ollamaSetupStage, double ollamaSetupProgress, String? ollamaSetupError
});


$EnglishFeedbackEntityCopyWith<$Res>? get feedback;

}
/// @nodoc
class _$LiveTranscriptionStateCopyWithImpl<$Res>
    implements $LiveTranscriptionStateCopyWith<$Res> {
  _$LiveTranscriptionStateCopyWithImpl(this._self, this._then);

  final LiveTranscriptionState _self;
  final $Res Function(LiveTranscriptionState) _then;

/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? segments = null,Object? isRecording = null,Object? isPaused = null,Object? duration = null,Object? serverState = null,Object? sessionTitle = freezed,Object? micPermission = null,Object? screenRecordingPermission = null,Object? isCoachEnabled = null,Object? isTranslationEnabled = null,Object? translationFrom = null,Object? translationTo = null,Object? translations = null,Object? feedback = freezed,Object? isFeedbackLoading = null,Object? ollamaSetupStage = null,Object? ollamaSetupProgress = null,Object? ollamaSetupError = freezed,}) {
  return _then(_self.copyWith(
segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<TranscriptSegmentEntity>,isRecording: null == isRecording ? _self.isRecording : isRecording // ignore: cast_nullable_to_non_nullable
as bool,isPaused: null == isPaused ? _self.isPaused : isPaused // ignore: cast_nullable_to_non_nullable
as bool,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,serverState: null == serverState ? _self.serverState : serverState // ignore: cast_nullable_to_non_nullable
as ServerState,sessionTitle: freezed == sessionTitle ? _self.sessionTitle : sessionTitle // ignore: cast_nullable_to_non_nullable
as String?,micPermission: null == micPermission ? _self.micPermission : micPermission // ignore: cast_nullable_to_non_nullable
as String,screenRecordingPermission: null == screenRecordingPermission ? _self.screenRecordingPermission : screenRecordingPermission // ignore: cast_nullable_to_non_nullable
as String,isCoachEnabled: null == isCoachEnabled ? _self.isCoachEnabled : isCoachEnabled // ignore: cast_nullable_to_non_nullable
as bool,isTranslationEnabled: null == isTranslationEnabled ? _self.isTranslationEnabled : isTranslationEnabled // ignore: cast_nullable_to_non_nullable
as bool,translationFrom: null == translationFrom ? _self.translationFrom : translationFrom // ignore: cast_nullable_to_non_nullable
as String,translationTo: null == translationTo ? _self.translationTo : translationTo // ignore: cast_nullable_to_non_nullable
as String,translations: null == translations ? _self.translations : translations // ignore: cast_nullable_to_non_nullable
as Map<String, String>,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as EnglishFeedbackEntity?,isFeedbackLoading: null == isFeedbackLoading ? _self.isFeedbackLoading : isFeedbackLoading // ignore: cast_nullable_to_non_nullable
as bool,ollamaSetupStage: null == ollamaSetupStage ? _self.ollamaSetupStage : ollamaSetupStage // ignore: cast_nullable_to_non_nullable
as OllamaSetupStage,ollamaSetupProgress: null == ollamaSetupProgress ? _self.ollamaSetupProgress : ollamaSetupProgress // ignore: cast_nullable_to_non_nullable
as double,ollamaSetupError: freezed == ollamaSetupError ? _self.ollamaSetupError : ollamaSetupError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EnglishFeedbackEntityCopyWith<$Res>? get feedback {
    if (_self.feedback == null) {
    return null;
  }

  return $EnglishFeedbackEntityCopyWith<$Res>(_self.feedback!, (value) {
    return _then(_self.copyWith(feedback: value));
  });
}
}


/// Adds pattern-matching-related methods to [LiveTranscriptionState].
extension LiveTranscriptionStatePatterns on LiveTranscriptionState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LiveTranscriptionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LiveTranscriptionState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LiveTranscriptionState value)  $default,){
final _that = this;
switch (_that) {
case _LiveTranscriptionState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LiveTranscriptionState value)?  $default,){
final _that = this;
switch (_that) {
case _LiveTranscriptionState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<TranscriptSegmentEntity> segments,  bool isRecording,  bool isPaused,  Duration duration,  ServerState serverState,  String? sessionTitle,  String micPermission,  String screenRecordingPermission,  bool isCoachEnabled,  bool isTranslationEnabled,  String translationFrom,  String translationTo,  Map<String, String> translations,  EnglishFeedbackEntity? feedback,  bool isFeedbackLoading,  OllamaSetupStage ollamaSetupStage,  double ollamaSetupProgress,  String? ollamaSetupError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LiveTranscriptionState() when $default != null:
return $default(_that.segments,_that.isRecording,_that.isPaused,_that.duration,_that.serverState,_that.sessionTitle,_that.micPermission,_that.screenRecordingPermission,_that.isCoachEnabled,_that.isTranslationEnabled,_that.translationFrom,_that.translationTo,_that.translations,_that.feedback,_that.isFeedbackLoading,_that.ollamaSetupStage,_that.ollamaSetupProgress,_that.ollamaSetupError);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<TranscriptSegmentEntity> segments,  bool isRecording,  bool isPaused,  Duration duration,  ServerState serverState,  String? sessionTitle,  String micPermission,  String screenRecordingPermission,  bool isCoachEnabled,  bool isTranslationEnabled,  String translationFrom,  String translationTo,  Map<String, String> translations,  EnglishFeedbackEntity? feedback,  bool isFeedbackLoading,  OllamaSetupStage ollamaSetupStage,  double ollamaSetupProgress,  String? ollamaSetupError)  $default,) {final _that = this;
switch (_that) {
case _LiveTranscriptionState():
return $default(_that.segments,_that.isRecording,_that.isPaused,_that.duration,_that.serverState,_that.sessionTitle,_that.micPermission,_that.screenRecordingPermission,_that.isCoachEnabled,_that.isTranslationEnabled,_that.translationFrom,_that.translationTo,_that.translations,_that.feedback,_that.isFeedbackLoading,_that.ollamaSetupStage,_that.ollamaSetupProgress,_that.ollamaSetupError);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<TranscriptSegmentEntity> segments,  bool isRecording,  bool isPaused,  Duration duration,  ServerState serverState,  String? sessionTitle,  String micPermission,  String screenRecordingPermission,  bool isCoachEnabled,  bool isTranslationEnabled,  String translationFrom,  String translationTo,  Map<String, String> translations,  EnglishFeedbackEntity? feedback,  bool isFeedbackLoading,  OllamaSetupStage ollamaSetupStage,  double ollamaSetupProgress,  String? ollamaSetupError)?  $default,) {final _that = this;
switch (_that) {
case _LiveTranscriptionState() when $default != null:
return $default(_that.segments,_that.isRecording,_that.isPaused,_that.duration,_that.serverState,_that.sessionTitle,_that.micPermission,_that.screenRecordingPermission,_that.isCoachEnabled,_that.isTranslationEnabled,_that.translationFrom,_that.translationTo,_that.translations,_that.feedback,_that.isFeedbackLoading,_that.ollamaSetupStage,_that.ollamaSetupProgress,_that.ollamaSetupError);case _:
  return null;

}
}

}

/// @nodoc


class _LiveTranscriptionState implements LiveTranscriptionState {
  const _LiveTranscriptionState({required final  List<TranscriptSegmentEntity> segments, this.isRecording = false, this.isPaused = false, this.duration = Duration.zero, this.serverState = ServerState.stopped, this.sessionTitle, this.micPermission = 'unknown', this.screenRecordingPermission = 'unknown', this.isCoachEnabled = false, this.isTranslationEnabled = false, this.translationFrom = 'en', this.translationTo = 'fr', final  Map<String, String> translations = const <String, String>{}, this.feedback, this.isFeedbackLoading = false, this.ollamaSetupStage = OllamaSetupStage.idle, this.ollamaSetupProgress = 0.0, this.ollamaSetupError}): _segments = segments,_translations = translations;
  

/// Liste des segments de transcription de la session courante.
 final  List<TranscriptSegmentEntity> _segments;
/// Liste des segments de transcription de la session courante.
@override List<TranscriptSegmentEntity> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}

/// Indique si un enregistrement est en cours.
@override@JsonKey() final  bool isRecording;
/// Indique si l'enregistrement est en pause.
@override@JsonKey() final  bool isPaused;
/// Duree actuelle de la session.
@override@JsonKey() final  Duration duration;
/// Etat du serveur de transcription.
@override@JsonKey() final  ServerState serverState;
/// Titre de la session en cours.
@override final  String? sessionTitle;
/// Statut de la permission microphone.
/// Valeurs : "authorized", "denied", "notDetermined", "restricted", "unknown".
@override@JsonKey() final  String micPermission;
/// Statut de la permission Screen Recording.
/// Valeurs : "authorized", "denied", "notDetermined", "unknown".
@override@JsonKey() final  String screenRecordingPermission;
/// Indique si l'option coach d'anglais est activée.
@override@JsonKey() final  bool isCoachEnabled;
/// Indique si la traduction temps réel est activée.
@override@JsonKey() final  bool isTranslationEnabled;
/// Langue source de la traduction (code ISO, ex: "en").
@override@JsonKey() final  String translationFrom;
/// Langue cible de la traduction (code ISO, ex: "fr").
@override@JsonKey() final  String translationTo;
/// Traductions par segment (id segment → texte traduit).
 final  Map<String, String> _translations;
/// Traductions par segment (id segment → texte traduit).
@override@JsonKey() Map<String, String> get translations {
  if (_translations is EqualUnmodifiableMapView) return _translations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_translations);
}

/// Retour du coach d'anglais (null si pas encore généré).
@override final  EnglishFeedbackEntity? feedback;
/// Indique si l'analyse de l'anglais est en cours.
@override@JsonKey() final  bool isFeedbackLoading;
/// Étape courante du setup Ollama.
@override@JsonKey() final  OllamaSetupStage ollamaSetupStage;
/// Progression du setup Ollama (0.0 – 1.0).
@override@JsonKey() final  double ollamaSetupProgress;
/// Message d'erreur du setup Ollama.
@override final  String? ollamaSetupError;

/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveTranscriptionStateCopyWith<_LiveTranscriptionState> get copyWith => __$LiveTranscriptionStateCopyWithImpl<_LiveTranscriptionState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveTranscriptionState&&const DeepCollectionEquality().equals(other._segments, _segments)&&(identical(other.isRecording, isRecording) || other.isRecording == isRecording)&&(identical(other.isPaused, isPaused) || other.isPaused == isPaused)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.serverState, serverState) || other.serverState == serverState)&&(identical(other.sessionTitle, sessionTitle) || other.sessionTitle == sessionTitle)&&(identical(other.micPermission, micPermission) || other.micPermission == micPermission)&&(identical(other.screenRecordingPermission, screenRecordingPermission) || other.screenRecordingPermission == screenRecordingPermission)&&(identical(other.isCoachEnabled, isCoachEnabled) || other.isCoachEnabled == isCoachEnabled)&&(identical(other.isTranslationEnabled, isTranslationEnabled) || other.isTranslationEnabled == isTranslationEnabled)&&(identical(other.translationFrom, translationFrom) || other.translationFrom == translationFrom)&&(identical(other.translationTo, translationTo) || other.translationTo == translationTo)&&const DeepCollectionEquality().equals(other._translations, _translations)&&(identical(other.feedback, feedback) || other.feedback == feedback)&&(identical(other.isFeedbackLoading, isFeedbackLoading) || other.isFeedbackLoading == isFeedbackLoading)&&(identical(other.ollamaSetupStage, ollamaSetupStage) || other.ollamaSetupStage == ollamaSetupStage)&&(identical(other.ollamaSetupProgress, ollamaSetupProgress) || other.ollamaSetupProgress == ollamaSetupProgress)&&(identical(other.ollamaSetupError, ollamaSetupError) || other.ollamaSetupError == ollamaSetupError));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_segments),isRecording,isPaused,duration,serverState,sessionTitle,micPermission,screenRecordingPermission,isCoachEnabled,isTranslationEnabled,translationFrom,translationTo,const DeepCollectionEquality().hash(_translations),feedback,isFeedbackLoading,ollamaSetupStage,ollamaSetupProgress,ollamaSetupError);

@override
String toString() {
  return 'LiveTranscriptionState(segments: $segments, isRecording: $isRecording, isPaused: $isPaused, duration: $duration, serverState: $serverState, sessionTitle: $sessionTitle, micPermission: $micPermission, screenRecordingPermission: $screenRecordingPermission, isCoachEnabled: $isCoachEnabled, isTranslationEnabled: $isTranslationEnabled, translationFrom: $translationFrom, translationTo: $translationTo, translations: $translations, feedback: $feedback, isFeedbackLoading: $isFeedbackLoading, ollamaSetupStage: $ollamaSetupStage, ollamaSetupProgress: $ollamaSetupProgress, ollamaSetupError: $ollamaSetupError)';
}


}

/// @nodoc
abstract mixin class _$LiveTranscriptionStateCopyWith<$Res> implements $LiveTranscriptionStateCopyWith<$Res> {
  factory _$LiveTranscriptionStateCopyWith(_LiveTranscriptionState value, $Res Function(_LiveTranscriptionState) _then) = __$LiveTranscriptionStateCopyWithImpl;
@override @useResult
$Res call({
 List<TranscriptSegmentEntity> segments, bool isRecording, bool isPaused, Duration duration, ServerState serverState, String? sessionTitle, String micPermission, String screenRecordingPermission, bool isCoachEnabled, bool isTranslationEnabled, String translationFrom, String translationTo, Map<String, String> translations, EnglishFeedbackEntity? feedback, bool isFeedbackLoading, OllamaSetupStage ollamaSetupStage, double ollamaSetupProgress, String? ollamaSetupError
});


@override $EnglishFeedbackEntityCopyWith<$Res>? get feedback;

}
/// @nodoc
class __$LiveTranscriptionStateCopyWithImpl<$Res>
    implements _$LiveTranscriptionStateCopyWith<$Res> {
  __$LiveTranscriptionStateCopyWithImpl(this._self, this._then);

  final _LiveTranscriptionState _self;
  final $Res Function(_LiveTranscriptionState) _then;

/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? segments = null,Object? isRecording = null,Object? isPaused = null,Object? duration = null,Object? serverState = null,Object? sessionTitle = freezed,Object? micPermission = null,Object? screenRecordingPermission = null,Object? isCoachEnabled = null,Object? isTranslationEnabled = null,Object? translationFrom = null,Object? translationTo = null,Object? translations = null,Object? feedback = freezed,Object? isFeedbackLoading = null,Object? ollamaSetupStage = null,Object? ollamaSetupProgress = null,Object? ollamaSetupError = freezed,}) {
  return _then(_LiveTranscriptionState(
segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<TranscriptSegmentEntity>,isRecording: null == isRecording ? _self.isRecording : isRecording // ignore: cast_nullable_to_non_nullable
as bool,isPaused: null == isPaused ? _self.isPaused : isPaused // ignore: cast_nullable_to_non_nullable
as bool,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,serverState: null == serverState ? _self.serverState : serverState // ignore: cast_nullable_to_non_nullable
as ServerState,sessionTitle: freezed == sessionTitle ? _self.sessionTitle : sessionTitle // ignore: cast_nullable_to_non_nullable
as String?,micPermission: null == micPermission ? _self.micPermission : micPermission // ignore: cast_nullable_to_non_nullable
as String,screenRecordingPermission: null == screenRecordingPermission ? _self.screenRecordingPermission : screenRecordingPermission // ignore: cast_nullable_to_non_nullable
as String,isCoachEnabled: null == isCoachEnabled ? _self.isCoachEnabled : isCoachEnabled // ignore: cast_nullable_to_non_nullable
as bool,isTranslationEnabled: null == isTranslationEnabled ? _self.isTranslationEnabled : isTranslationEnabled // ignore: cast_nullable_to_non_nullable
as bool,translationFrom: null == translationFrom ? _self.translationFrom : translationFrom // ignore: cast_nullable_to_non_nullable
as String,translationTo: null == translationTo ? _self.translationTo : translationTo // ignore: cast_nullable_to_non_nullable
as String,translations: null == translations ? _self._translations : translations // ignore: cast_nullable_to_non_nullable
as Map<String, String>,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as EnglishFeedbackEntity?,isFeedbackLoading: null == isFeedbackLoading ? _self.isFeedbackLoading : isFeedbackLoading // ignore: cast_nullable_to_non_nullable
as bool,ollamaSetupStage: null == ollamaSetupStage ? _self.ollamaSetupStage : ollamaSetupStage // ignore: cast_nullable_to_non_nullable
as OllamaSetupStage,ollamaSetupProgress: null == ollamaSetupProgress ? _self.ollamaSetupProgress : ollamaSetupProgress // ignore: cast_nullable_to_non_nullable
as double,ollamaSetupError: freezed == ollamaSetupError ? _self.ollamaSetupError : ollamaSetupError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of LiveTranscriptionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EnglishFeedbackEntityCopyWith<$Res>? get feedback {
    if (_self.feedback == null) {
    return null;
  }

  return $EnglishFeedbackEntityCopyWith<$Res>(_self.feedback!, (value) {
    return _then(_self.copyWith(feedback: value));
  });
}
}

// dart format on
