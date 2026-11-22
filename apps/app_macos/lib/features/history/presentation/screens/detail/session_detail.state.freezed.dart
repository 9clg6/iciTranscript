// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_detail.state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionDetailState {

/// La session affichee.
 SessionEntity? get session;/// Les segments de transcription de la session.
 List<TranscriptSegmentEntity> get segments;/// Indique si le titre est en cours d'edition.
 bool get isEditing;/// Resume IA de la session, null si absent.
 String? get summary;/// Retour du coach d'anglais, null si absent.
 EnglishFeedbackEntity? get feedback;/// Indique si la generation du resume est en cours.
 bool get isSummaryLoading;/// Indique si l'analyse du coach d'anglais est en cours.
 bool get isFeedbackLoading;/// Tours de parole diarizes du meeting (Interlocuteur N).
 List<SpeakerTurn> get speakers;/// Un modele (en ligne ou local installe) peut repondre ; sinon la note
/// invite a en configurer un.
 bool get llmAvailable;/// Cle du message d'erreur du dernier resume (`llm.error.*`).
 String? get summaryError;/// Le dernier resume semble coupe : affiche, signale, non range.
 bool get summaryIncomplete;/// Cle du message d'erreur du dernier retour du coach (`llm.error.*`).
 String? get feedbackError;
/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionDetailStateCopyWith<SessionDetailState> get copyWith => _$SessionDetailStateCopyWithImpl<SessionDetailState>(this as SessionDetailState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionDetailState&&(identical(other.session, session) || other.session == session)&&const DeepCollectionEquality().equals(other.segments, segments)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.feedback, feedback) || other.feedback == feedback)&&(identical(other.isSummaryLoading, isSummaryLoading) || other.isSummaryLoading == isSummaryLoading)&&(identical(other.isFeedbackLoading, isFeedbackLoading) || other.isFeedbackLoading == isFeedbackLoading)&&const DeepCollectionEquality().equals(other.speakers, speakers)&&(identical(other.llmAvailable, llmAvailable) || other.llmAvailable == llmAvailable)&&(identical(other.summaryError, summaryError) || other.summaryError == summaryError)&&(identical(other.summaryIncomplete, summaryIncomplete) || other.summaryIncomplete == summaryIncomplete)&&(identical(other.feedbackError, feedbackError) || other.feedbackError == feedbackError));
}


@override
int get hashCode => Object.hash(runtimeType,session,const DeepCollectionEquality().hash(segments),isEditing,summary,feedback,isSummaryLoading,isFeedbackLoading,const DeepCollectionEquality().hash(speakers),llmAvailable,summaryError,summaryIncomplete,feedbackError);

@override
String toString() {
  return 'SessionDetailState(session: $session, segments: $segments, isEditing: $isEditing, summary: $summary, feedback: $feedback, isSummaryLoading: $isSummaryLoading, isFeedbackLoading: $isFeedbackLoading, speakers: $speakers, llmAvailable: $llmAvailable, summaryError: $summaryError, summaryIncomplete: $summaryIncomplete, feedbackError: $feedbackError)';
}


}

/// @nodoc
abstract mixin class $SessionDetailStateCopyWith<$Res>  {
  factory $SessionDetailStateCopyWith(SessionDetailState value, $Res Function(SessionDetailState) _then) = _$SessionDetailStateCopyWithImpl;
@useResult
$Res call({
 SessionEntity? session, List<TranscriptSegmentEntity> segments, bool isEditing, String? summary, EnglishFeedbackEntity? feedback, bool isSummaryLoading, bool isFeedbackLoading, List<SpeakerTurn> speakers, bool llmAvailable, String? summaryError, bool summaryIncomplete, String? feedbackError
});


$SessionEntityCopyWith<$Res>? get session;$EnglishFeedbackEntityCopyWith<$Res>? get feedback;

}
/// @nodoc
class _$SessionDetailStateCopyWithImpl<$Res>
    implements $SessionDetailStateCopyWith<$Res> {
  _$SessionDetailStateCopyWithImpl(this._self, this._then);

  final SessionDetailState _self;
  final $Res Function(SessionDetailState) _then;

/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? session = freezed,Object? segments = null,Object? isEditing = null,Object? summary = freezed,Object? feedback = freezed,Object? isSummaryLoading = null,Object? isFeedbackLoading = null,Object? speakers = null,Object? llmAvailable = null,Object? summaryError = freezed,Object? summaryIncomplete = null,Object? feedbackError = freezed,}) {
  return _then(_self.copyWith(
session: freezed == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionEntity?,segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<TranscriptSegmentEntity>,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as EnglishFeedbackEntity?,isSummaryLoading: null == isSummaryLoading ? _self.isSummaryLoading : isSummaryLoading // ignore: cast_nullable_to_non_nullable
as bool,isFeedbackLoading: null == isFeedbackLoading ? _self.isFeedbackLoading : isFeedbackLoading // ignore: cast_nullable_to_non_nullable
as bool,speakers: null == speakers ? _self.speakers : speakers // ignore: cast_nullable_to_non_nullable
as List<SpeakerTurn>,llmAvailable: null == llmAvailable ? _self.llmAvailable : llmAvailable // ignore: cast_nullable_to_non_nullable
as bool,summaryError: freezed == summaryError ? _self.summaryError : summaryError // ignore: cast_nullable_to_non_nullable
as String?,summaryIncomplete: null == summaryIncomplete ? _self.summaryIncomplete : summaryIncomplete // ignore: cast_nullable_to_non_nullable
as bool,feedbackError: freezed == feedbackError ? _self.feedbackError : feedbackError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionEntityCopyWith<$Res>? get session {
    if (_self.session == null) {
    return null;
  }

  return $SessionEntityCopyWith<$Res>(_self.session!, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of SessionDetailState
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


/// Adds pattern-matching-related methods to [SessionDetailState].
extension SessionDetailStatePatterns on SessionDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionDetailState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionDetailState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionDetailState value)  $default,){
final _that = this;
switch (_that) {
case _SessionDetailState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionDetailState value)?  $default,){
final _that = this;
switch (_that) {
case _SessionDetailState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionEntity? session,  List<TranscriptSegmentEntity> segments,  bool isEditing,  String? summary,  EnglishFeedbackEntity? feedback,  bool isSummaryLoading,  bool isFeedbackLoading,  List<SpeakerTurn> speakers,  bool llmAvailable,  String? summaryError,  bool summaryIncomplete,  String? feedbackError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionDetailState() when $default != null:
return $default(_that.session,_that.segments,_that.isEditing,_that.summary,_that.feedback,_that.isSummaryLoading,_that.isFeedbackLoading,_that.speakers,_that.llmAvailable,_that.summaryError,_that.summaryIncomplete,_that.feedbackError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionEntity? session,  List<TranscriptSegmentEntity> segments,  bool isEditing,  String? summary,  EnglishFeedbackEntity? feedback,  bool isSummaryLoading,  bool isFeedbackLoading,  List<SpeakerTurn> speakers,  bool llmAvailable,  String? summaryError,  bool summaryIncomplete,  String? feedbackError)  $default,) {final _that = this;
switch (_that) {
case _SessionDetailState():
return $default(_that.session,_that.segments,_that.isEditing,_that.summary,_that.feedback,_that.isSummaryLoading,_that.isFeedbackLoading,_that.speakers,_that.llmAvailable,_that.summaryError,_that.summaryIncomplete,_that.feedbackError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionEntity? session,  List<TranscriptSegmentEntity> segments,  bool isEditing,  String? summary,  EnglishFeedbackEntity? feedback,  bool isSummaryLoading,  bool isFeedbackLoading,  List<SpeakerTurn> speakers,  bool llmAvailable,  String? summaryError,  bool summaryIncomplete,  String? feedbackError)?  $default,) {final _that = this;
switch (_that) {
case _SessionDetailState() when $default != null:
return $default(_that.session,_that.segments,_that.isEditing,_that.summary,_that.feedback,_that.isSummaryLoading,_that.isFeedbackLoading,_that.speakers,_that.llmAvailable,_that.summaryError,_that.summaryIncomplete,_that.feedbackError);case _:
  return null;

}
}

}

/// @nodoc


class _SessionDetailState implements SessionDetailState {
  const _SessionDetailState({this.session, required final  List<TranscriptSegmentEntity> segments, this.isEditing = false, this.summary, this.feedback, this.isSummaryLoading = false, this.isFeedbackLoading = false, final  List<SpeakerTurn> speakers = const <SpeakerTurn>[], this.llmAvailable = false, this.summaryError, this.summaryIncomplete = false, this.feedbackError}): _segments = segments,_speakers = speakers;
  

/// La session affichee.
@override final  SessionEntity? session;
/// Les segments de transcription de la session.
 final  List<TranscriptSegmentEntity> _segments;
/// Les segments de transcription de la session.
@override List<TranscriptSegmentEntity> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}

/// Indique si le titre est en cours d'edition.
@override@JsonKey() final  bool isEditing;
/// Resume IA de la session, null si absent.
@override final  String? summary;
/// Retour du coach d'anglais, null si absent.
@override final  EnglishFeedbackEntity? feedback;
/// Indique si la generation du resume est en cours.
@override@JsonKey() final  bool isSummaryLoading;
/// Indique si l'analyse du coach d'anglais est en cours.
@override@JsonKey() final  bool isFeedbackLoading;
/// Tours de parole diarizes du meeting (Interlocuteur N).
 final  List<SpeakerTurn> _speakers;
/// Tours de parole diarizes du meeting (Interlocuteur N).
@override@JsonKey() List<SpeakerTurn> get speakers {
  if (_speakers is EqualUnmodifiableListView) return _speakers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_speakers);
}

/// Un modele (en ligne ou local installe) peut repondre ; sinon la note
/// invite a en configurer un.
@override@JsonKey() final  bool llmAvailable;
/// Cle du message d'erreur du dernier resume (`llm.error.*`).
@override final  String? summaryError;
/// Le dernier resume semble coupe : affiche, signale, non range.
@override@JsonKey() final  bool summaryIncomplete;
/// Cle du message d'erreur du dernier retour du coach (`llm.error.*`).
@override final  String? feedbackError;

/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionDetailStateCopyWith<_SessionDetailState> get copyWith => __$SessionDetailStateCopyWithImpl<_SessionDetailState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionDetailState&&(identical(other.session, session) || other.session == session)&&const DeepCollectionEquality().equals(other._segments, _segments)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.feedback, feedback) || other.feedback == feedback)&&(identical(other.isSummaryLoading, isSummaryLoading) || other.isSummaryLoading == isSummaryLoading)&&(identical(other.isFeedbackLoading, isFeedbackLoading) || other.isFeedbackLoading == isFeedbackLoading)&&const DeepCollectionEquality().equals(other._speakers, _speakers)&&(identical(other.llmAvailable, llmAvailable) || other.llmAvailable == llmAvailable)&&(identical(other.summaryError, summaryError) || other.summaryError == summaryError)&&(identical(other.summaryIncomplete, summaryIncomplete) || other.summaryIncomplete == summaryIncomplete)&&(identical(other.feedbackError, feedbackError) || other.feedbackError == feedbackError));
}


@override
int get hashCode => Object.hash(runtimeType,session,const DeepCollectionEquality().hash(_segments),isEditing,summary,feedback,isSummaryLoading,isFeedbackLoading,const DeepCollectionEquality().hash(_speakers),llmAvailable,summaryError,summaryIncomplete,feedbackError);

@override
String toString() {
  return 'SessionDetailState(session: $session, segments: $segments, isEditing: $isEditing, summary: $summary, feedback: $feedback, isSummaryLoading: $isSummaryLoading, isFeedbackLoading: $isFeedbackLoading, speakers: $speakers, llmAvailable: $llmAvailable, summaryError: $summaryError, summaryIncomplete: $summaryIncomplete, feedbackError: $feedbackError)';
}


}

/// @nodoc
abstract mixin class _$SessionDetailStateCopyWith<$Res> implements $SessionDetailStateCopyWith<$Res> {
  factory _$SessionDetailStateCopyWith(_SessionDetailState value, $Res Function(_SessionDetailState) _then) = __$SessionDetailStateCopyWithImpl;
@override @useResult
$Res call({
 SessionEntity? session, List<TranscriptSegmentEntity> segments, bool isEditing, String? summary, EnglishFeedbackEntity? feedback, bool isSummaryLoading, bool isFeedbackLoading, List<SpeakerTurn> speakers, bool llmAvailable, String? summaryError, bool summaryIncomplete, String? feedbackError
});


@override $SessionEntityCopyWith<$Res>? get session;@override $EnglishFeedbackEntityCopyWith<$Res>? get feedback;

}
/// @nodoc
class __$SessionDetailStateCopyWithImpl<$Res>
    implements _$SessionDetailStateCopyWith<$Res> {
  __$SessionDetailStateCopyWithImpl(this._self, this._then);

  final _SessionDetailState _self;
  final $Res Function(_SessionDetailState) _then;

/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? session = freezed,Object? segments = null,Object? isEditing = null,Object? summary = freezed,Object? feedback = freezed,Object? isSummaryLoading = null,Object? isFeedbackLoading = null,Object? speakers = null,Object? llmAvailable = null,Object? summaryError = freezed,Object? summaryIncomplete = null,Object? feedbackError = freezed,}) {
  return _then(_SessionDetailState(
session: freezed == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionEntity?,segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<TranscriptSegmentEntity>,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as EnglishFeedbackEntity?,isSummaryLoading: null == isSummaryLoading ? _self.isSummaryLoading : isSummaryLoading // ignore: cast_nullable_to_non_nullable
as bool,isFeedbackLoading: null == isFeedbackLoading ? _self.isFeedbackLoading : isFeedbackLoading // ignore: cast_nullable_to_non_nullable
as bool,speakers: null == speakers ? _self._speakers : speakers // ignore: cast_nullable_to_non_nullable
as List<SpeakerTurn>,llmAvailable: null == llmAvailable ? _self.llmAvailable : llmAvailable // ignore: cast_nullable_to_non_nullable
as bool,summaryError: freezed == summaryError ? _self.summaryError : summaryError // ignore: cast_nullable_to_non_nullable
as String?,summaryIncomplete: null == summaryIncomplete ? _self.summaryIncomplete : summaryIncomplete // ignore: cast_nullable_to_non_nullable
as bool,feedbackError: freezed == feedbackError ? _self.feedbackError : feedbackError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of SessionDetailState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionEntityCopyWith<$Res>? get session {
    if (_self.session == null) {
    return null;
  }

  return $SessionEntityCopyWith<$Res>(_self.session!, (value) {
    return _then(_self.copyWith(session: value));
  });
}/// Create a copy of SessionDetailState
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
