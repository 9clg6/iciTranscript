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
 String get explanation;
/// Create a copy of EnglishCorrectionEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnglishCorrectionEntityCopyWith<EnglishCorrectionEntity> get copyWith => _$EnglishCorrectionEntityCopyWithImpl<EnglishCorrectionEntity>(this as EnglishCorrectionEntity, _$identity);

  /// Serializes this EnglishCorrectionEntity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnglishCorrectionEntity&&(identical(other.original, original) || other.original == original)&&(identical(other.corrected, corrected) || other.corrected == corrected)&&(identical(other.category, category) || other.category == category)&&(identical(other.explanation, explanation) || other.explanation == explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,original,corrected,category,explanation);

@override
String toString() {
  return 'EnglishCorrectionEntity(original: $original, corrected: $corrected, category: $category, explanation: $explanation)';
}


}

/// @nodoc
abstract mixin class $EnglishCorrectionEntityCopyWith<$Res>  {
  factory $EnglishCorrectionEntityCopyWith(EnglishCorrectionEntity value, $Res Function(EnglishCorrectionEntity) _then) = _$EnglishCorrectionEntityCopyWithImpl;
@useResult
$Res call({
 String original, String corrected, String category, String explanation
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
@pragma('vm:prefer-inline') @override $Res call({Object? original = null,Object? corrected = null,Object? category = null,Object? explanation = null,}) {
  return _then(_self.copyWith(
original: null == original ? _self.original : original // ignore: cast_nullable_to_non_nullable
as String,corrected: null == corrected ? _self.corrected : corrected // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String original,  String corrected,  String category,  String explanation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
return $default(_that.original,_that.corrected,_that.category,_that.explanation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String original,  String corrected,  String category,  String explanation)  $default,) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity():
return $default(_that.original,_that.corrected,_that.category,_that.explanation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String original,  String corrected,  String category,  String explanation)?  $default,) {final _that = this;
switch (_that) {
case _EnglishCorrectionEntity() when $default != null:
return $default(_that.original,_that.corrected,_that.category,_that.explanation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnglishCorrectionEntity implements EnglishCorrectionEntity {
  const _EnglishCorrectionEntity({required this.original, required this.corrected, required this.category, required this.explanation});
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnglishCorrectionEntity&&(identical(other.original, original) || other.original == original)&&(identical(other.corrected, corrected) || other.corrected == corrected)&&(identical(other.category, category) || other.category == category)&&(identical(other.explanation, explanation) || other.explanation == explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,original,corrected,category,explanation);

@override
String toString() {
  return 'EnglishCorrectionEntity(original: $original, corrected: $corrected, category: $category, explanation: $explanation)';
}


}

/// @nodoc
abstract mixin class _$EnglishCorrectionEntityCopyWith<$Res> implements $EnglishCorrectionEntityCopyWith<$Res> {
  factory _$EnglishCorrectionEntityCopyWith(_EnglishCorrectionEntity value, $Res Function(_EnglishCorrectionEntity) _then) = __$EnglishCorrectionEntityCopyWithImpl;
@override @useResult
$Res call({
 String original, String corrected, String category, String explanation
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
@override @pragma('vm:prefer-inline') $Res call({Object? original = null,Object? corrected = null,Object? category = null,Object? explanation = null,}) {
  return _then(_EnglishCorrectionEntity(
original: null == original ? _self.original : original // ignore: cast_nullable_to_non_nullable
as String,corrected: null == corrected ? _self.corrected : corrected // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$EnglishFeedbackEntity {

/// Liste des corrections proposees.
 List<EnglishCorrectionEntity> get corrections;/// Appreciation globale du niveau (optionnelle).
 String? get overall;
/// Create a copy of EnglishFeedbackEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnglishFeedbackEntityCopyWith<EnglishFeedbackEntity> get copyWith => _$EnglishFeedbackEntityCopyWithImpl<EnglishFeedbackEntity>(this as EnglishFeedbackEntity, _$identity);

  /// Serializes this EnglishFeedbackEntity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnglishFeedbackEntity&&const DeepCollectionEquality().equals(other.corrections, corrections)&&(identical(other.overall, overall) || other.overall == overall));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(corrections),overall);

@override
String toString() {
  return 'EnglishFeedbackEntity(corrections: $corrections, overall: $overall)';
}


}

/// @nodoc
abstract mixin class $EnglishFeedbackEntityCopyWith<$Res>  {
  factory $EnglishFeedbackEntityCopyWith(EnglishFeedbackEntity value, $Res Function(EnglishFeedbackEntity) _then) = _$EnglishFeedbackEntityCopyWithImpl;
@useResult
$Res call({
 List<EnglishCorrectionEntity> corrections, String? overall
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
@pragma('vm:prefer-inline') @override $Res call({Object? corrections = null,Object? overall = freezed,}) {
  return _then(_self.copyWith(
corrections: null == corrections ? _self.corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<EnglishCorrectionEntity>,overall: freezed == overall ? _self.overall : overall // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<EnglishCorrectionEntity> corrections,  String? overall)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
return $default(_that.corrections,_that.overall);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<EnglishCorrectionEntity> corrections,  String? overall)  $default,) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity():
return $default(_that.corrections,_that.overall);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<EnglishCorrectionEntity> corrections,  String? overall)?  $default,) {final _that = this;
switch (_that) {
case _EnglishFeedbackEntity() when $default != null:
return $default(_that.corrections,_that.overall);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EnglishFeedbackEntity implements EnglishFeedbackEntity {
  const _EnglishFeedbackEntity({final  List<EnglishCorrectionEntity> corrections = const <EnglishCorrectionEntity>[], this.overall}): _corrections = corrections;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnglishFeedbackEntity&&const DeepCollectionEquality().equals(other._corrections, _corrections)&&(identical(other.overall, overall) || other.overall == overall));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_corrections),overall);

@override
String toString() {
  return 'EnglishFeedbackEntity(corrections: $corrections, overall: $overall)';
}


}

/// @nodoc
abstract mixin class _$EnglishFeedbackEntityCopyWith<$Res> implements $EnglishFeedbackEntityCopyWith<$Res> {
  factory _$EnglishFeedbackEntityCopyWith(_EnglishFeedbackEntity value, $Res Function(_EnglishFeedbackEntity) _then) = __$EnglishFeedbackEntityCopyWithImpl;
@override @useResult
$Res call({
 List<EnglishCorrectionEntity> corrections, String? overall
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
@override @pragma('vm:prefer-inline') $Res call({Object? corrections = null,Object? overall = freezed,}) {
  return _then(_EnglishFeedbackEntity(
corrections: null == corrections ? _self._corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<EnglishCorrectionEntity>,overall: freezed == overall ? _self.overall : overall // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
