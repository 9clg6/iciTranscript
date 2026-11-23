// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'english_feedback.entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EnglishCorrectionEntity {

/// Phrase ou tournure telle que prononcee par l'utilisateur.
 String get original;/// Version corrigee / amelioree proposee.
 String get corrected;/// Categorie libre renvoyee par le modele
/// (ex: conjugation, vocabulary, expression, grammar).
 String get category;/// Explication courte de la correction (en francais).
 String get explanation;/// Heure, dans la note, de la phrase qui contient [original] (ms depuis
/// le début, comme `TranscriptSegmentEntity.timestampMs`) ; null si
/// inconnue (retour d'avant, phrase introuvable).
 int? get timestampMs;
/// Create a copy of EnglishCorrectionEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnglishCorrectionEntityCopyWith<EnglishCorrectionEntity> get copyWith => _$EnglishCorrectionEntityCopyWithImpl<EnglishCorrectionEntity>(this as EnglishCorrectionEntity, _$identity);

  /// Serializes this EnglishCorrectionEntity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnglishCorrectionEntity&&(identical(other.original, original) || other.original == original)&&(identical(other.corrected, corrected) || other.corrected == corrected)&&(identical(other.category, category) || other.category == category)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,original,corrected,category,explanation,timestampMs);

@override
String toString() {
  return 'EnglishCorrectionEntity(original: $original, corrected: $corrected, category: $category, explanation: $explanation, timestampMs: $timestampMs)';
}


}

/// @nodoc
abstract mixin class $EnglishCorrectionEntityCopyWith<$Res>  {
  factory $EnglishCorrectionEntityCopyWith(EnglishCorrectionEntity value, $Res Function(EnglishCorrectionEntity) _then) = _$EnglishCorrectionEntityCopyWithImpl;
@useResult
$Res call({
 String original, String corrected, String category, String explanation, int? timestampMs
});




}
/// @nodoc
class _$EnglishCorrectionEntityCopyWithImpl<$Res>
    implements $EnglishCorrectionEntityCopyWith<$Res> {
  _$EnglishCorrectionEntityCopyWithImpl(this._self, this._then);

  final EnglishCorrectionEntity _self;
  final $Res Function(EnglishCorrectionEntity) _then;

/// Create a copy of EnglishCorrectionEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? original = null,Object? corrected = null,Object? category = null,Object? explanation = null,Object? timestampMs = freezed,}) {
  return _then(_self.copyWith(
original: null == original ? _self.original : original // ignore: cast_nullable_to_non_nullable
as String,corrected: null == corrected ? _self.corrected : corrected // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,timestampMs: freezed == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [EnglishCorrectionEntity].
extension EnglishCorrectionEntityPatterns on EnglishCorrectionEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EnglishCorrectionEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EnglishCorrectionEntity value)  $default,){
final _that = this;
switch (_that) {
case _EnglishCorrectionEntity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EnglishCorrectionEntity value)?  $default,){
final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String original,  String corrected,  String category,  String explanation,  int? timestampMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
return $default(_that.original,_that.corrected,_that.category,_that.explanation,_that.timestampMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String original,  String corrected,  String category,  String explanation,  int? timestampMs)  $default,) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity():
return $default(_that.original,_that.corrected,_that.category,_that.explanation,_that.timestampMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String original,  String corrected,  String category,  String explanation,  int? timestampMs)?  $default,) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
return $default(_that.original,_that.corrected,_that.category,_that.explanation,_that.timestampMs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnglishCorrectionEntity implements EnglishCorrectionEntity {
  const _EnglishCorrectionEntity({required this.original, required this.corrected, required this.category, required this.explanation, this.timestampMs});
  factory _EnglishCorrectionEntity.fromJson(Map<String, dynamic> json) => _$EnglishCorrectionEntityFromJson(json);

/// Phrase ou tournure telle que prononcee par l'utilisateur.
@override final  String original;
/// Version corrigee / amelioree proposee.
@override final  String corrected;
/// Categorie libre renvoyee par le modele
/// (ex: conjugation, vocabulary, expression, grammar).
@override final  String category;
/// Explication courte de la correction (en francais).
@override final  String explanation;
/// Heure, dans la note, de la phrase qui contient [original] (ms depuis
/// le début, comme `TranscriptSegmentEntity.timestampMs`) ; null si
/// inconnue (retour d'avant, phrase introuvable).
@override final  int? timestampMs;

/// Create a copy of EnglishCorrectionEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EnglishCorrectionEntityCopyWith<_EnglishCorrectionEntity> get copyWith => __$EnglishCorrectionEntityCopyWithImpl<_EnglishCorrectionEntity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EnglishCorrectionEntityToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnglishCorrectionEntity&&(identical(other.original, original) || other.original == original)&&(identical(other.corrected, corrected) || other.corrected == corrected)&&(identical(other.category, category) || other.category == category)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,original,corrected,category,explanation,timestampMs);

@override
String toString() {
  return 'EnglishCorrectionEntity(original: $original, corrected: $corrected, category: $category, explanation: $explanation, timestampMs: $timestampMs)';
}


}

/// @nodoc
abstract mixin class _$EnglishCorrectionEntityCopyWith<$Res> implements $EnglishCorrectionEntityCopyWith<$Res> {
  factory _$EnglishCorrectionEntityCopyWith(_EnglishCorrectionEntity value, $Res Function(_EnglishCorrectionEntity) _then) = __$EnglishCorrectionEntityCopyWithImpl;
@override @useResult
$Res call({
 String original, String corrected, String category, String explanation, int? timestampMs
});




}
/// @nodoc
class __$EnglishCorrectionEntityCopyWithImpl<$Res>
    implements _$EnglishCorrectionEntityCopyWith<$Res> {
  __$EnglishCorrectionEntityCopyWithImpl(this._self, this._then);

  final _EnglishCorrectionEntity _self;
  final $Res Function(_EnglishCorrectionEntity) _then;

/// Create a copy of EnglishCorrectionEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? original = null,Object? corrected = null,Object? category = null,Object? explanation = null,Object? timestampMs = freezed,}) {
  return _then(_EnglishCorrectionEntity(
original: null == original ? _self.original : original // ignore: cast_nullable_to_non_nullable
as String,corrected: null == corrected ? _self.corrected : corrected // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,timestampMs: freezed == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$EnglishFeedbackEntity {

/// Liste des corrections proposees.
 List<EnglishCorrectionEntity> get corrections;/// Appreciation globale du niveau (optionnelle).
 String? get overall;/// Phrases (ids de segments) dont la partie n'a pas pu être analysée
/// (lot en échec) : la note propose de réessayer.
 List<String> get unanalyzedSegmentIds;
/// Create a copy of EnglishFeedbackEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnglishFeedbackEntityCopyWith<EnglishFeedbackEntity> get copyWith => _$EnglishFeedbackEntityCopyWithImpl<EnglishFeedbackEntity>(this as EnglishFeedbackEntity, _$identity);

  /// Serializes this EnglishFeedbackEntity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnglishFeedbackEntity&&const DeepCollectionEquality().equals(other.corrections, corrections)&&(identical(other.overall, overall) || other.overall == overall)&&const DeepCollectionEquality().equals(other.unanalyzedSegmentIds, unanalyzedSegmentIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(corrections),overall,const DeepCollectionEquality().hash(unanalyzedSegmentIds));

@override
String toString() {
  return 'EnglishFeedbackEntity(corrections: $corrections, overall: $overall, unanalyzedSegmentIds: $unanalyzedSegmentIds)';
}


}

/// @nodoc
abstract mixin class $EnglishFeedbackEntityCopyWith<$Res>  {
  factory $EnglishFeedbackEntityCopyWith(EnglishFeedbackEntity value, $Res Function(EnglishFeedbackEntity) _then) = _$EnglishFeedbackEntityCopyWithImpl;
@useResult
$Res call({
 List<EnglishCorrectionEntity> corrections, String? overall, List<String> unanalyzedSegmentIds
});




}
/// @nodoc
class _$EnglishFeedbackEntityCopyWithImpl<$Res>
    implements $EnglishFeedbackEntityCopyWith<$Res> {
  _$EnglishFeedbackEntityCopyWithImpl(this._self, this._then);

  final EnglishFeedbackEntity _self;
  final $Res Function(EnglishFeedbackEntity) _then;

/// Create a copy of EnglishFeedbackEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? corrections = null,Object? overall = freezed,Object? unanalyzedSegmentIds = null,}) {
  return _then(_self.copyWith(
corrections: null == corrections ? _self.corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<EnglishCorrectionEntity>,overall: freezed == overall ? _self.overall : overall // ignore: cast_nullable_to_non_nullable
as String?,unanalyzedSegmentIds: null == unanalyzedSegmentIds ? _self.unanalyzedSegmentIds : unanalyzedSegmentIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [EnglishFeedbackEntity].
extension EnglishFeedbackEntityPatterns on EnglishFeedbackEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EnglishFeedbackEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EnglishFeedbackEntity value)  $default,){
final _that = this;
switch (_that) {
case _EnglishFeedbackEntity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EnglishFeedbackEntity value)?  $default,){
final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<EnglishCorrectionEntity> corrections,  String? overall,  List<String> unanalyzedSegmentIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
return $default(_that.corrections,_that.overall,_that.unanalyzedSegmentIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<EnglishCorrectionEntity> corrections,  String? overall,  List<String> unanalyzedSegmentIds)  $default,) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity():
return $default(_that.corrections,_that.overall,_that.unanalyzedSegmentIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<EnglishCorrectionEntity> corrections,  String? overall,  List<String> unanalyzedSegmentIds)?  $default,) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
return $default(_that.corrections,_that.overall,_that.unanalyzedSegmentIds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnglishFeedbackEntity implements EnglishFeedbackEntity {
  const _EnglishFeedbackEntity({final  List<EnglishCorrectionEntity> corrections = const <EnglishCorrectionEntity>[], this.overall, final  List<String> unanalyzedSegmentIds = const <String>[]}): _corrections = corrections,_unanalyzedSegmentIds = unanalyzedSegmentIds;
  factory _EnglishFeedbackEntity.fromJson(Map<String, dynamic> json) => _$EnglishFeedbackEntityFromJson(json);

/// Liste des corrections proposees.
 final  List<EnglishCorrectionEntity> _corrections;
/// Liste des corrections proposees.
@override@JsonKey() List<EnglishCorrectionEntity> get corrections {
  if (_corrections is EqualUnmodifiableListView) return _corrections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_corrections);
}

/// Appreciation globale du niveau (optionnelle).
@override final  String? overall;
/// Phrases (ids de segments) dont la partie n'a pas pu être analysée
/// (lot en échec) : la note propose de réessayer.
 final  List<String> _unanalyzedSegmentIds;
/// Phrases (ids de segments) dont la partie n'a pas pu être analysée
/// (lot en échec) : la note propose de réessayer.
@override@JsonKey() List<String> get unanalyzedSegmentIds {
  if (_unanalyzedSegmentIds is EqualUnmodifiableListView) return _unanalyzedSegmentIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unanalyzedSegmentIds);
}


/// Create a copy of EnglishFeedbackEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EnglishFeedbackEntityCopyWith<_EnglishFeedbackEntity> get copyWith => __$EnglishFeedbackEntityCopyWithImpl<_EnglishFeedbackEntity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EnglishFeedbackEntityToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnglishFeedbackEntity&&const DeepCollectionEquality().equals(other._corrections, _corrections)&&(identical(other.overall, overall) || other.overall == overall)&&const DeepCollectionEquality().equals(other._unanalyzedSegmentIds, _unanalyzedSegmentIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_corrections),overall,const DeepCollectionEquality().hash(_unanalyzedSegmentIds));

@override
String toString() {
  return 'EnglishFeedbackEntity(corrections: $corrections, overall: $overall, unanalyzedSegmentIds: $unanalyzedSegmentIds)';
}


}

/// @nodoc
abstract mixin class _$EnglishFeedbackEntityCopyWith<$Res> implements $EnglishFeedbackEntityCopyWith<$Res> {
  factory _$EnglishFeedbackEntityCopyWith(_EnglishFeedbackEntity value, $Res Function(_EnglishFeedbackEntity) _then) = __$EnglishFeedbackEntityCopyWithImpl;
@override @useResult
$Res call({
 List<EnglishCorrectionEntity> corrections, String? overall, List<String> unanalyzedSegmentIds
});




}
/// @nodoc
class __$EnglishFeedbackEntityCopyWithImpl<$Res>
    implements _$EnglishFeedbackEntityCopyWith<$Res> {
  __$EnglishFeedbackEntityCopyWithImpl(this._self, this._then);

  final _EnglishFeedbackEntity _self;
  final $Res Function(_EnglishFeedbackEntity) _then;

/// Create a copy of EnglishFeedbackEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? corrections = null,Object? overall = freezed,Object? unanalyzedSegmentIds = null,}) {
  return _then(_EnglishFeedbackEntity(
corrections: null == corrections ? _self._corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<EnglishCorrectionEntity>,overall: freezed == overall ? _self.overall : overall // ignore: cast_nullable_to_non_nullable
as String?,unanalyzedSegmentIds: null == unanalyzedSegmentIds ? _self._unanalyzedSegmentIds : unanalyzedSegmentIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
