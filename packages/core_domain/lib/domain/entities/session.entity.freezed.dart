// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.entity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionEntity {

/// Identifiant unique de la session.
 String get id;/// Titre de la session.
 String get title;/// Date de creation de la session.
 DateTime get createdAt;/// Date de derniere mise a jour de la session.
 DateTime get updatedAt;/// Duree totale de la session en secondes.
 int? get durationSeconds;/// Statut actuel de la session.
 SessionStatus get status;/// Identifiant de l'evenement d'agenda lie (occurrence), ou null.
 String? get calendarEventId;/// Titre de l'evenement d'agenda lie, ou null.
 String? get calendarEventTitle;/// Noms des participants de l'evenement lie (jamais d'adresse e-mail).
 List<String> get attendees;
/// Create a copy of SessionEntity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionEntityCopyWith<SessionEntity> get copyWith => _$SessionEntityCopyWithImpl<SessionEntity>(this as SessionEntity, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionEntity&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.status, status) || other.status == status)&&(identical(other.calendarEventId, calendarEventId) || other.calendarEventId == calendarEventId)&&(identical(other.calendarEventTitle, calendarEventTitle) || other.calendarEventTitle == calendarEventTitle)&&const DeepCollectionEquality().equals(other.attendees, attendees));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,createdAt,updatedAt,durationSeconds,status,calendarEventId,calendarEventTitle,const DeepCollectionEquality().hash(attendees));

@override
String toString() {
  return 'SessionEntity(id: $id, title: $title, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, status: $status, calendarEventId: $calendarEventId, calendarEventTitle: $calendarEventTitle, attendees: $attendees)';
}


}

/// @nodoc
abstract mixin class $SessionEntityCopyWith<$Res>  {
  factory $SessionEntityCopyWith(SessionEntity value, $Res Function(SessionEntity) _then) = _$SessionEntityCopyWithImpl;
@useResult
$Res call({
 String id, String title, DateTime createdAt, DateTime updatedAt, int? durationSeconds, SessionStatus status, String? calendarEventId, String? calendarEventTitle, List<String> attendees
});




}
/// @nodoc
class _$SessionEntityCopyWithImpl<$Res>
    implements $SessionEntityCopyWith<$Res> {
  _$SessionEntityCopyWithImpl(this._self, this._then);

  final SessionEntity _self;
  final $Res Function(SessionEntity) _then;

/// Create a copy of SessionEntity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = freezed,Object? status = null,Object? calendarEventId = freezed,Object? calendarEventTitle = freezed,Object? attendees = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionStatus,calendarEventId: freezed == calendarEventId ? _self.calendarEventId : calendarEventId // ignore: cast_nullable_to_non_nullable
as String?,calendarEventTitle: freezed == calendarEventTitle ? _self.calendarEventTitle : calendarEventTitle // ignore: cast_nullable_to_non_nullable
as String?,attendees: null == attendees ? _self.attendees : attendees // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionEntity].
extension SessionEntityPatterns on SessionEntity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionEntity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionEntity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionEntity value)  $default,){
final _that = this;
switch (_that) {
case _SessionEntity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionEntity value)?  $default,){
final _that = this;
switch (_that) {
case _SessionEntity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  DateTime createdAt,  DateTime updatedAt,  int? durationSeconds,  SessionStatus status,  String? calendarEventId,  String? calendarEventTitle,  List<String> attendees)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionEntity() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  DateTime createdAt,  DateTime updatedAt,  int? durationSeconds,  SessionStatus status,  String? calendarEventId,  String? calendarEventTitle,  List<String> attendees)  $default,) {final _that = this;
switch (_that) {
case _SessionEntity():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  DateTime createdAt,  DateTime updatedAt,  int? durationSeconds,  SessionStatus status,  String? calendarEventId,  String? calendarEventTitle,  List<String> attendees)?  $default,) {final _that = this;
switch (_that) {
case _SessionEntity() when $default != null:
return $default(_that.id,_that.title,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.status,_that.calendarEventId,_that.calendarEventTitle,_that.attendees);case _:
  return null;

}
}

}

/// @nodoc


class _SessionEntity implements SessionEntity {
  const _SessionEntity({required this.id, required this.title, required this.createdAt, required this.updatedAt, this.durationSeconds, required this.status, this.calendarEventId, this.calendarEventTitle, final  List<String> attendees = const <String>[]}): _attendees = attendees;
  

/// Identifiant unique de la session.
@override final  String id;
/// Titre de la session.
@override final  String title;
/// Date de creation de la session.
@override final  DateTime createdAt;
/// Date de derniere mise a jour de la session.
@override final  DateTime updatedAt;
/// Duree totale de la session en secondes.
@override final  int? durationSeconds;
/// Statut actuel de la session.
@override final  SessionStatus status;
/// Identifiant de l'evenement d'agenda lie (occurrence), ou null.
@override final  String? calendarEventId;
/// Titre de l'evenement d'agenda lie, ou null.
@override final  String? calendarEventTitle;
/// Noms des participants de l'evenement lie (jamais d'adresse e-mail).
 final  List<String> _attendees;
/// Noms des participants de l'evenement lie (jamais d'adresse e-mail).
@override@JsonKey() List<String> get attendees {
  if (_attendees is EqualUnmodifiableListView) return _attendees;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attendees);
}


/// Create a copy of SessionEntity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionEntityCopyWith<_SessionEntity> get copyWith => __$SessionEntityCopyWithImpl<_SessionEntity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionEntity&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.status, status) || other.status == status)&&(identical(other.calendarEventId, calendarEventId) || other.calendarEventId == calendarEventId)&&(identical(other.calendarEventTitle, calendarEventTitle) || other.calendarEventTitle == calendarEventTitle)&&const DeepCollectionEquality().equals(other._attendees, _attendees));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,createdAt,updatedAt,durationSeconds,status,calendarEventId,calendarEventTitle,const DeepCollectionEquality().hash(_attendees));

@override
String toString() {
  return 'SessionEntity(id: $id, title: $title, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, status: $status, calendarEventId: $calendarEventId, calendarEventTitle: $calendarEventTitle, attendees: $attendees)';
}


}

/// @nodoc
abstract mixin class _$SessionEntityCopyWith<$Res> implements $SessionEntityCopyWith<$Res> {
  factory _$SessionEntityCopyWith(_SessionEntity value, $Res Function(_SessionEntity) _then) = __$SessionEntityCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, DateTime createdAt, DateTime updatedAt, int? durationSeconds, SessionStatus status, String? calendarEventId, String? calendarEventTitle, List<String> attendees
});




}
/// @nodoc
class __$SessionEntityCopyWithImpl<$Res>
    implements _$SessionEntityCopyWith<$Res> {
  __$SessionEntityCopyWithImpl(this._self, this._then);

  final _SessionEntity _self;
  final $Res Function(_SessionEntity) _then;

/// Create a copy of SessionEntity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = freezed,Object? status = null,Object? calendarEventId = freezed,Object? calendarEventTitle = freezed,Object? attendees = null,}) {
  return _then(_SessionEntity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionStatus,calendarEventId: freezed == calendarEventId ? _self.calendarEventId : calendarEventId // ignore: cast_nullable_to_non_nullable
as String?,calendarEventTitle: freezed == calendarEventTitle ? _self.calendarEventTitle : calendarEventTitle // ignore: cast_nullable_to_non_nullable
as String?,attendees: null == attendees ? _self._attendees : attendees // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
