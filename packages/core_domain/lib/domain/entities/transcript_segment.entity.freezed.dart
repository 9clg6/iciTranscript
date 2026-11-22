// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transcript_segment.entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TranscriptSegmentEntity {

/// Identifiant unique du segment.
 String get id;/// Identifiant de la session parente.
 String get sessionId;/// Source audio du segment (micro ou systeme).
 AudioSource get source;/// Texte transcrit.
 String get text;/// Offset en millisecondes depuis le debut de la session.
 int get timestampMs;/// Date de creation du segment.
 DateTime get createdAt;/// Texte connu incomplet : phrase en cours sauvée, ou scellée par une
/// coupure ou un arrêt brutal. Le rattrapage depuis le WAV remplace ces
/// segments au lieu de les laisser à côté du texte retrouvé.
 bool get isPartial;
/// Create a copy of TranscriptSegmentEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranscriptSegmentEntityCopyWith<TranscriptSegmentEntity> get copyWith => _$TranscriptSegmentEntityCopyWithImpl<TranscriptSegmentEntity>(this as TranscriptSegmentEntity, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranscriptSegmentEntity&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.source, source) || other.source == source)&&(identical(other.text, text) || other.text == text)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isPartial, isPartial) || other.isPartial == isPartial));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,source,text,timestampMs,createdAt,isPartial);

@override
String toString() {
  return 'TranscriptSegmentEntity(id: $id, sessionId: $sessionId, source: $source, text: $text, timestampMs: $timestampMs, createdAt: $createdAt, isPartial: $isPartial)';
}


}

/// @nodoc
abstract mixin class $TranscriptSegmentEntityCopyWith<$Res>  {
  factory $TranscriptSegmentEntityCopyWith(TranscriptSegmentEntity value, $Res Function(TranscriptSegmentEntity) _then) = _$TranscriptSegmentEntityCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, AudioSource source, String text, int timestampMs, DateTime createdAt, bool isPartial
});




}
/// @nodoc
class _$TranscriptSegmentEntityCopyWithImpl<$Res>
    implements $TranscriptSegmentEntityCopyWith<$Res> {
  _$TranscriptSegmentEntityCopyWithImpl(this._self, this._then);

  final TranscriptSegmentEntity _self;
  final $Res Function(TranscriptSegmentEntity) _then;

/// Create a copy of TranscriptSegmentEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? source = null,Object? text = null,Object? timestampMs = null,Object? createdAt = null,Object? isPartial = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AudioSource,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,timestampMs: null == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isPartial: null == isPartial ? _self.isPartial : isPartial // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TranscriptSegmentEntity].
extension TranscriptSegmentEntityPatterns on TranscriptSegmentEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranscriptSegmentEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranscriptSegmentEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranscriptSegmentEntity value)  $default,){
final _that = this;
switch (_that) {
case _TranscriptSegmentEntity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranscriptSegmentEntity value)?  $default,){
final _that = this;
switch (_that) {
case _TranscriptSegmentEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  AudioSource source,  String text,  int timestampMs,  DateTime createdAt,  bool isPartial)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranscriptSegmentEntity() when $default != null:
return $default(_that.id,_that.sessionId,_that.source,_that.text,_that.timestampMs,_that.createdAt,_that.isPartial);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  AudioSource source,  String text,  int timestampMs,  DateTime createdAt,  bool isPartial)  $default,) {final _that = this;
switch (_that) {
case _TranscriptSegmentEntity():
return $default(_that.id,_that.sessionId,_that.source,_that.text,_that.timestampMs,_that.createdAt,_that.isPartial);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  AudioSource source,  String text,  int timestampMs,  DateTime createdAt,  bool isPartial)?  $default,) {final _that = this;
switch (_that) {
case _TranscriptSegmentEntity() when $default != null:
return $default(_that.id,_that.sessionId,_that.source,_that.text,_that.timestampMs,_that.createdAt,_that.isPartial);case _:
  return null;

}
}

}

/// @nodoc


class _TranscriptSegmentEntity implements TranscriptSegmentEntity {
  const _TranscriptSegmentEntity({required this.id, required this.sessionId, required this.source, required this.text, required this.timestampMs, required this.createdAt, this.isPartial = false});
  

/// Identifiant unique du segment.
@override final  String id;
/// Identifiant de la session parente.
@override final  String sessionId;
/// Source audio du segment (micro ou systeme).
@override final  AudioSource source;
/// Texte transcrit.
@override final  String text;
/// Offset en millisecondes depuis le debut de la session.
@override final  int timestampMs;
/// Date de creation du segment.
@override final  DateTime createdAt;
/// Texte connu incomplet : phrase en cours sauvée, ou scellée par une
/// coupure ou un arrêt brutal. Le rattrapage depuis le WAV remplace ces
/// segments au lieu de les laisser à côté du texte retrouvé.
@override@JsonKey() final  bool isPartial;

/// Create a copy of TranscriptSegmentEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranscriptSegmentEntityCopyWith<_TranscriptSegmentEntity> get copyWith => __$TranscriptSegmentEntityCopyWithImpl<_TranscriptSegmentEntity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranscriptSegmentEntity&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.source, source) || other.source == source)&&(identical(other.text, text) || other.text == text)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isPartial, isPartial) || other.isPartial == isPartial));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,source,text,timestampMs,createdAt,isPartial);

@override
String toString() {
  return 'TranscriptSegmentEntity(id: $id, sessionId: $sessionId, source: $source, text: $text, timestampMs: $timestampMs, createdAt: $createdAt, isPartial: $isPartial)';
}


}

/// @nodoc
abstract mixin class _$TranscriptSegmentEntityCopyWith<$Res> implements $TranscriptSegmentEntityCopyWith<$Res> {
  factory _$TranscriptSegmentEntityCopyWith(_TranscriptSegmentEntity value, $Res Function(_TranscriptSegmentEntity) _then) = __$TranscriptSegmentEntityCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, AudioSource source, String text, int timestampMs, DateTime createdAt, bool isPartial
});




}
/// @nodoc
class __$TranscriptSegmentEntityCopyWithImpl<$Res>
    implements _$TranscriptSegmentEntityCopyWith<$Res> {
  __$TranscriptSegmentEntityCopyWithImpl(this._self, this._then);

  final _TranscriptSegmentEntity _self;
  final $Res Function(_TranscriptSegmentEntity) _then;

/// Create a copy of TranscriptSegmentEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? source = null,Object? text = null,Object? timestampMs = null,Object? createdAt = null,Object? isPartial = null,}) {
  return _then(_TranscriptSegmentEntity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AudioSource,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,timestampMs: null == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isPartial: null == isPartial ? _self.isPartial : isPartial // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
