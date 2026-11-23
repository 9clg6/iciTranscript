// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.local.model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SessionLocalModel {

/// Identifiant unique de la session.
 String get id;/// Titre de la session.
 String get title;/// Date de creation au format ISO 8601.
 String get createdAt;/// Date de derniere mise a jour au format ISO 8601.
 String get updatedAt;/// Duree totale en secondes.
 int? get durationSeconds;/// Statut de la session (active, completed, error).
 String get status;/// Identifiant de l'evenement d'agenda lie.
 String? get calendarEventId;/// Titre de l'evenement d'agenda lie.
 String? get calendarEventTitle;/// Noms des participants, tableau JSON (null = aucun).
 String? get attendees;
/// Create a copy of SessionLocalModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionLocalModelCopyWith<SessionLocalModel> get copyWith => _$SessionLocalModelCopyWithImpl<SessionLocalModel>(this as SessionLocalModel, _$identity);

  /// Serializes this SessionLocalModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionLocalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.status, status) || other.status == status)&&(identical(other.calendarEventId, calendarEventId) || other.calendarEventId == calendarEventId)&&(identical(other.calendarEventTitle, calendarEventTitle) || other.calendarEventTitle == calendarEventTitle)&&(identical(other.attendees, attendees) || other.attendees == attendees));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,createdAt,updatedAt,durationSeconds,status,calendarEventId,calendarEventTitle,attendees);

@override
String toString() {
  return 'SessionLocalModel(id: $id, title: $title, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, status: $status, calendarEventId: $calendarEventId, calendarEventTitle: $calendarEventTitle, attendees: $attendees)';
}


}

/// @nodoc
abstract mixin class $SessionLocalModelCopyWith<$Res>  {
  factory $SessionLocalModelCopyWith(SessionLocalModel value, $Res Function(SessionLocalModel) _then) = _$SessionLocalModelCopyWithImpl;
@useResult
$Res call({
 String id, String title, String createdAt, String updatedAt, int? durationSeconds, String status, String? calendarEventId, String? calendarEventTitle, String? attendees
});




}
/// @nodoc
class _$SessionLocalModelCopyWithImpl<$Res>
    implements $SessionLocalModelCopyWith<$Res> {
  _$SessionLocalModelCopyWithImpl(this._self, this._then);

  final SessionLocalModel _self;
  final $Res Function(SessionLocalModel) _then;

/// Create a copy of SessionLocalModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = freezed,Object? status = null,Object? calendarEventId = freezed,Object? calendarEventTitle = freezed,Object? attendees = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,calendarEventId: freezed == calendarEventId ? _self.calendarEventId : calendarEventId // ignore: cast_nullable_to_non_nullable
as String?,calendarEventTitle: freezed == calendarEventTitle ? _self.calendarEventTitle : calendarEventTitle // ignore: cast_nullable_to_non_nullable
as String?,attendees: freezed == attendees ? _self.attendees : attendees // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionLocalModel].
extension SessionLocalModelPatterns on SessionLocalModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionLocalModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionLocalModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionLocalModel value)  $default,){
final _that = this;
switch (_that) {
case _SessionLocalModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionLocalModel value)?  $default,){
final _that = this;
switch (_that) {
case _SessionLocalModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String createdAt,  String updatedAt,  int? durationSeconds,  String status,  String? calendarEventId,  String? calendarEventTitle,  String? attendees)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionLocalModel() when $default != null:
return $default(_that.id,_that.title,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.status,_that.calendarEventId,_that.calendarEventTitle,_that.attendees);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String createdAt,  String updatedAt,  int? durationSeconds,  String status,  String? calendarEventId,  String? calendarEventTitle,  String? attendees)  $default,) {final _that = this;
switch (_that) {
case _SessionLocalModel():
return $default(_that.id,_that.title,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.status,_that.calendarEventId,_that.calendarEventTitle,_that.attendees);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String createdAt,  String updatedAt,  int? durationSeconds,  String status,  String? calendarEventId,  String? calendarEventTitle,  String? attendees)?  $default,) {final _that = this;
switch (_that) {
case _SessionLocalModel() when $default != null:
return $default(_that.id,_that.title,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.status,_that.calendarEventId,_that.calendarEventTitle,_that.attendees);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SessionLocalModel implements SessionLocalModel {
  const _SessionLocalModel({required this.id, required this.title, required this.createdAt, required this.updatedAt, this.durationSeconds, required this.status, this.calendarEventId, this.calendarEventTitle, this.attendees});
  factory _SessionLocalModel.fromJson(Map<String, dynamic> json) => _$SessionLocalModelFromJson(json);

/// Identifiant unique de la session.
@override final  String id;
/// Titre de la session.
@override final  String title;
/// Date de creation au format ISO 8601.
@override final  String createdAt;
/// Date de derniere mise a jour au format ISO 8601.
@override final  String updatedAt;
/// Duree totale en secondes.
@override final  int? durationSeconds;
/// Statut de la session (active, completed, error).
@override final  String status;
/// Identifiant de l'evenement d'agenda lie.
@override final  String? calendarEventId;
/// Titre de l'evenement d'agenda lie.
@override final  String? calendarEventTitle;
/// Noms des participants, tableau JSON (null = aucun).
@override final  String? attendees;

/// Create a copy of SessionLocalModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionLocalModelCopyWith<_SessionLocalModel> get copyWith => __$SessionLocalModelCopyWithImpl<_SessionLocalModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SessionLocalModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionLocalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.status, status) || other.status == status)&&(identical(other.calendarEventId, calendarEventId) || other.calendarEventId == calendarEventId)&&(identical(other.calendarEventTitle, calendarEventTitle) || other.calendarEventTitle == calendarEventTitle)&&(identical(other.attendees, attendees) || other.attendees == attendees));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,createdAt,updatedAt,durationSeconds,status,calendarEventId,calendarEventTitle,attendees);

@override
String toString() {
  return 'SessionLocalModel(id: $id, title: $title, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, status: $status, calendarEventId: $calendarEventId, calendarEventTitle: $calendarEventTitle, attendees: $attendees)';
}


}

/// @nodoc
abstract mixin class _$SessionLocalModelCopyWith<$Res> implements $SessionLocalModelCopyWith<$Res> {
  factory _$SessionLocalModelCopyWith(_SessionLocalModel value, $Res Function(_SessionLocalModel) _then) = __$SessionLocalModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String createdAt, String updatedAt, int? durationSeconds, String status, String? calendarEventId, String? calendarEventTitle, String? attendees
});




}
/// @nodoc
class __$SessionLocalModelCopyWithImpl<$Res>
    implements _$SessionLocalModelCopyWith<$Res> {
  __$SessionLocalModelCopyWithImpl(this._self, this._then);

  final _SessionLocalModel _self;
  final $Res Function(_SessionLocalModel) _then;

/// Create a copy of SessionLocalModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = freezed,Object? status = null,Object? calendarEventId = freezed,Object? calendarEventTitle = freezed,Object? attendees = freezed,}) {
  return _then(_SessionLocalModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,calendarEventId: freezed == calendarEventId ? _self.calendarEventId : calendarEventId // ignore: cast_nullable_to_non_nullable
as String?,calendarEventTitle: freezed == calendarEventTitle ? _self.calendarEventTitle : calendarEventTitle // ignore: cast_nullable_to_non_nullable
as String?,attendees: freezed == attendees ? _self.attendees : attendees // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
