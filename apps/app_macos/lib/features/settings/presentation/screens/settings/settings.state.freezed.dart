// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings.state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsState {

/// Identifiant du microphone selectionne.
 String? get selectedMicId;/// Indique si la capture audio systeme est activee.
 bool get systemAudioEnabled;/// Indique si le serveur ML doit demarrer automatiquement.
 bool get autoStartServer;/// Chemin de stockage de la base de donnees.
 String get storagePath;/// Taille de la base de donnees en Mo.
 double get dbSizeMb;/// Liste des peripheriques audio disponibles.
 List<AudioDeviceEntity> get availableDevices;
/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsStateCopyWith<SettingsState> get copyWith => _$SettingsStateCopyWithImpl<SettingsState>(this as SettingsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsState&&(identical(other.selectedMicId, selectedMicId) || other.selectedMicId == selectedMicId)&&(identical(other.systemAudioEnabled, systemAudioEnabled) || other.systemAudioEnabled == systemAudioEnabled)&&(identical(other.autoStartServer, autoStartServer) || other.autoStartServer == autoStartServer)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.dbSizeMb, dbSizeMb) || other.dbSizeMb == dbSizeMb)&&const DeepCollectionEquality().equals(other.availableDevices, availableDevices));
}


@override
int get hashCode => Object.hash(runtimeType,selectedMicId,systemAudioEnabled,autoStartServer,storagePath,dbSizeMb,const DeepCollectionEquality().hash(availableDevices));

@override
String toString() {
  return 'SettingsState(selectedMicId: $selectedMicId, systemAudioEnabled: $systemAudioEnabled, autoStartServer: $autoStartServer, storagePath: $storagePath, dbSizeMb: $dbSizeMb, availableDevices: $availableDevices)';
}


}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res>  {
  factory $SettingsStateCopyWith(SettingsState value, $Res Function(SettingsState) _then) = _$SettingsStateCopyWithImpl;
@useResult
$Res call({
 String? selectedMicId, bool systemAudioEnabled, bool autoStartServer, String storagePath, double dbSizeMb, List<AudioDeviceEntity> availableDevices
});




}
/// @nodoc
class _$SettingsStateCopyWithImpl<$Res>
    implements $SettingsStateCopyWith<$Res> {
  _$SettingsStateCopyWithImpl(this._self, this._then);

  final SettingsState _self;
  final $Res Function(SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedMicId = freezed,Object? systemAudioEnabled = null,Object? autoStartServer = null,Object? storagePath = null,Object? dbSizeMb = null,Object? availableDevices = null,}) {
  return _then(_self.copyWith(
selectedMicId: freezed == selectedMicId ? _self.selectedMicId : selectedMicId // ignore: cast_nullable_to_non_nullable
as String?,systemAudioEnabled: null == systemAudioEnabled ? _self.systemAudioEnabled : systemAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoStartServer: null == autoStartServer ? _self.autoStartServer : autoStartServer // ignore: cast_nullable_to_non_nullable
as bool,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,dbSizeMb: null == dbSizeMb ? _self.dbSizeMb : dbSizeMb // ignore: cast_nullable_to_non_nullable
as double,availableDevices: null == availableDevices ? _self.availableDevices : availableDevices // ignore: cast_nullable_to_non_nullable
as List<AudioDeviceEntity>,
  ));
}

}


/// Adds pattern-matching-related methods to [SettingsState].
extension SettingsStatePatterns on SettingsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsState value)  $default,){
final _that = this;
switch (_that) {
case _SettingsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsState value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.storagePath,_that.dbSizeMb,_that.availableDevices);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices)  $default,) {final _that = this;
switch (_that) {
case _SettingsState():
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.storagePath,_that.dbSizeMb,_that.availableDevices);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices)?  $default,) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.storagePath,_that.dbSizeMb,_that.availableDevices);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsState implements SettingsState {
  const _SettingsState({this.selectedMicId, this.systemAudioEnabled = true, this.autoStartServer = true, this.storagePath = '', this.dbSizeMb = 0.0, required final  List<AudioDeviceEntity> availableDevices}): _availableDevices = availableDevices;
  

/// Identifiant du microphone selectionne.
@override final  String? selectedMicId;
/// Indique si la capture audio systeme est activee.
@override@JsonKey() final  bool systemAudioEnabled;
/// Indique si le serveur ML doit demarrer automatiquement.
@override@JsonKey() final  bool autoStartServer;
/// Chemin de stockage de la base de donnees.
@override@JsonKey() final  String storagePath;
/// Taille de la base de donnees en Mo.
@override@JsonKey() final  double dbSizeMb;
/// Liste des peripheriques audio disponibles.
 final  List<AudioDeviceEntity> _availableDevices;
/// Liste des peripheriques audio disponibles.
@override List<AudioDeviceEntity> get availableDevices {
  if (_availableDevices is EqualUnmodifiableListView) return _availableDevices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableDevices);
}


/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsStateCopyWith<_SettingsState> get copyWith => __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsState&&(identical(other.selectedMicId, selectedMicId) || other.selectedMicId == selectedMicId)&&(identical(other.systemAudioEnabled, systemAudioEnabled) || other.systemAudioEnabled == systemAudioEnabled)&&(identical(other.autoStartServer, autoStartServer) || other.autoStartServer == autoStartServer)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.dbSizeMb, dbSizeMb) || other.dbSizeMb == dbSizeMb)&&const DeepCollectionEquality().equals(other._availableDevices, _availableDevices));
}


@override
int get hashCode => Object.hash(runtimeType,selectedMicId,systemAudioEnabled,autoStartServer,storagePath,dbSizeMb,const DeepCollectionEquality().hash(_availableDevices));

@override
String toString() {
  return 'SettingsState(selectedMicId: $selectedMicId, systemAudioEnabled: $systemAudioEnabled, autoStartServer: $autoStartServer, storagePath: $storagePath, dbSizeMb: $dbSizeMb, availableDevices: $availableDevices)';
}


}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res> implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(_SettingsState value, $Res Function(_SettingsState) _then) = __$SettingsStateCopyWithImpl;
@override @useResult
$Res call({
 String? selectedMicId, bool systemAudioEnabled, bool autoStartServer, String storagePath, double dbSizeMb, List<AudioDeviceEntity> availableDevices
});




}
/// @nodoc
class __$SettingsStateCopyWithImpl<$Res>
    implements _$SettingsStateCopyWith<$Res> {
  __$SettingsStateCopyWithImpl(this._self, this._then);

  final _SettingsState _self;
  final $Res Function(_SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedMicId = freezed,Object? systemAudioEnabled = null,Object? autoStartServer = null,Object? storagePath = null,Object? dbSizeMb = null,Object? availableDevices = null,}) {
  return _then(_SettingsState(
selectedMicId: freezed == selectedMicId ? _self.selectedMicId : selectedMicId // ignore: cast_nullable_to_non_nullable
as String?,systemAudioEnabled: null == systemAudioEnabled ? _self.systemAudioEnabled : systemAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoStartServer: null == autoStartServer ? _self.autoStartServer : autoStartServer // ignore: cast_nullable_to_non_nullable
as bool,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,dbSizeMb: null == dbSizeMb ? _self.dbSizeMb : dbSizeMb // ignore: cast_nullable_to_non_nullable
as double,availableDevices: null == availableDevices ? _self._availableDevices : availableDevices // ignore: cast_nullable_to_non_nullable
as List<AudioDeviceEntity>,
  ));
}


}

// dart format on
