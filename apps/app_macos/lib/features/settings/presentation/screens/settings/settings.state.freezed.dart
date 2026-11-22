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
 bool get autoStartServer;/// Port du serveur ML (voxmlx-serve default: 8000).
 String get serverPort;/// Chemin de stockage de la base de donnees.
 String get storagePath;/// Taille de la base de donnees en Mo.
 double get dbSizeMb;/// Liste des peripheriques audio disponibles.
 List<AudioDeviceEntity> get availableDevices;/// Envoi à un service LLM en ligne autorisé (coupé par défaut).
 bool get llmCloudAllowed;/// Fournisseur LLM choisi ; null = repli automatique.
 LlmProviderId? get llmPreferred;/// Fournisseur LLM réellement utilisé (choix, autorisation et clés).
 LlmProviderId get llmActive;/// Modèles choisis par fournisseur ; absent = modèle par défaut.
 Map<LlmProviderId, String> get llmModels;/// 4 derniers caractères de chaque clé rangée (jamais la clé entière).
 Map<LlmProviderId, String> get llmKeySuffixes;/// Fournisseurs dont le trousseau a refusé la lecture ou l'écriture.
 Set<LlmProviderId> get llmKeyErrors;/// Dernier résultat de « Tester » par fournisseur.
 Map<LlmProviderId, LlmTestStatus> get llmTests;
/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsStateCopyWith<SettingsState> get copyWith => _$SettingsStateCopyWithImpl<SettingsState>(this as SettingsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsState&&(identical(other.selectedMicId, selectedMicId) || other.selectedMicId == selectedMicId)&&(identical(other.systemAudioEnabled, systemAudioEnabled) || other.systemAudioEnabled == systemAudioEnabled)&&(identical(other.autoStartServer, autoStartServer) || other.autoStartServer == autoStartServer)&&(identical(other.serverPort, serverPort) || other.serverPort == serverPort)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.dbSizeMb, dbSizeMb) || other.dbSizeMb == dbSizeMb)&&const DeepCollectionEquality().equals(other.availableDevices, availableDevices)&&(identical(other.llmCloudAllowed, llmCloudAllowed) || other.llmCloudAllowed == llmCloudAllowed)&&(identical(other.llmPreferred, llmPreferred) || other.llmPreferred == llmPreferred)&&(identical(other.llmActive, llmActive) || other.llmActive == llmActive)&&const DeepCollectionEquality().equals(other.llmModels, llmModels)&&const DeepCollectionEquality().equals(other.llmKeySuffixes, llmKeySuffixes)&&const DeepCollectionEquality().equals(other.llmKeyErrors, llmKeyErrors)&&const DeepCollectionEquality().equals(other.llmTests, llmTests));
}


@override
int get hashCode => Object.hash(runtimeType,selectedMicId,systemAudioEnabled,autoStartServer,serverPort,storagePath,dbSizeMb,const DeepCollectionEquality().hash(availableDevices),llmCloudAllowed,llmPreferred,llmActive,const DeepCollectionEquality().hash(llmModels),const DeepCollectionEquality().hash(llmKeySuffixes),const DeepCollectionEquality().hash(llmKeyErrors),const DeepCollectionEquality().hash(llmTests));

@override
String toString() {
  return 'SettingsState(selectedMicId: $selectedMicId, systemAudioEnabled: $systemAudioEnabled, autoStartServer: $autoStartServer, serverPort: $serverPort, storagePath: $storagePath, dbSizeMb: $dbSizeMb, availableDevices: $availableDevices, llmCloudAllowed: $llmCloudAllowed, llmPreferred: $llmPreferred, llmActive: $llmActive, llmModels: $llmModels, llmKeySuffixes: $llmKeySuffixes, llmKeyErrors: $llmKeyErrors, llmTests: $llmTests)';
}


}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res>  {
  factory $SettingsStateCopyWith(SettingsState value, $Res Function(SettingsState) _then) = _$SettingsStateCopyWithImpl;
@useResult
$Res call({
 String? selectedMicId, bool systemAudioEnabled, bool autoStartServer, String serverPort, String storagePath, double dbSizeMb, List<AudioDeviceEntity> availableDevices, bool llmCloudAllowed, LlmProviderId? llmPreferred, LlmProviderId llmActive, Map<LlmProviderId, String> llmModels, Map<LlmProviderId, String> llmKeySuffixes, Set<LlmProviderId> llmKeyErrors, Map<LlmProviderId, LlmTestStatus> llmTests
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
@pragma('vm:prefer-inline') @override $Res call({Object? selectedMicId = freezed,Object? systemAudioEnabled = null,Object? autoStartServer = null,Object? serverPort = null,Object? storagePath = null,Object? dbSizeMb = null,Object? availableDevices = null,Object? llmCloudAllowed = null,Object? llmPreferred = freezed,Object? llmActive = null,Object? llmModels = null,Object? llmKeySuffixes = null,Object? llmKeyErrors = null,Object? llmTests = null,}) {
  return _then(_self.copyWith(
selectedMicId: freezed == selectedMicId ? _self.selectedMicId : selectedMicId // ignore: cast_nullable_to_non_nullable
as String?,systemAudioEnabled: null == systemAudioEnabled ? _self.systemAudioEnabled : systemAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoStartServer: null == autoStartServer ? _self.autoStartServer : autoStartServer // ignore: cast_nullable_to_non_nullable
as bool,serverPort: null == serverPort ? _self.serverPort : serverPort // ignore: cast_nullable_to_non_nullable
as String,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,dbSizeMb: null == dbSizeMb ? _self.dbSizeMb : dbSizeMb // ignore: cast_nullable_to_non_nullable
as double,availableDevices: null == availableDevices ? _self.availableDevices : availableDevices // ignore: cast_nullable_to_non_nullable
as List<AudioDeviceEntity>,llmCloudAllowed: null == llmCloudAllowed ? _self.llmCloudAllowed : llmCloudAllowed // ignore: cast_nullable_to_non_nullable
as bool,llmPreferred: freezed == llmPreferred ? _self.llmPreferred : llmPreferred // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,llmActive: null == llmActive ? _self.llmActive : llmActive // ignore: cast_nullable_to_non_nullable
as LlmProviderId,llmModels: null == llmModels ? _self.llmModels : llmModels // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, String>,llmKeySuffixes: null == llmKeySuffixes ? _self.llmKeySuffixes : llmKeySuffixes // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, String>,llmKeyErrors: null == llmKeyErrors ? _self.llmKeyErrors : llmKeyErrors // ignore: cast_nullable_to_non_nullable
as Set<LlmProviderId>,llmTests: null == llmTests ? _self.llmTests : llmTests // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, LlmTestStatus>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String serverPort,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices,  bool llmCloudAllowed,  LlmProviderId? llmPreferred,  LlmProviderId llmActive,  Map<LlmProviderId, String> llmModels,  Map<LlmProviderId, String> llmKeySuffixes,  Set<LlmProviderId> llmKeyErrors,  Map<LlmProviderId, LlmTestStatus> llmTests)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.serverPort,_that.storagePath,_that.dbSizeMb,_that.availableDevices,_that.llmCloudAllowed,_that.llmPreferred,_that.llmActive,_that.llmModels,_that.llmKeySuffixes,_that.llmKeyErrors,_that.llmTests);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String serverPort,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices,  bool llmCloudAllowed,  LlmProviderId? llmPreferred,  LlmProviderId llmActive,  Map<LlmProviderId, String> llmModels,  Map<LlmProviderId, String> llmKeySuffixes,  Set<LlmProviderId> llmKeyErrors,  Map<LlmProviderId, LlmTestStatus> llmTests)  $default,) {final _that = this;
switch (_that) {
case _SettingsState():
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.serverPort,_that.storagePath,_that.dbSizeMb,_that.availableDevices,_that.llmCloudAllowed,_that.llmPreferred,_that.llmActive,_that.llmModels,_that.llmKeySuffixes,_that.llmKeyErrors,_that.llmTests);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? selectedMicId,  bool systemAudioEnabled,  bool autoStartServer,  String serverPort,  String storagePath,  double dbSizeMb,  List<AudioDeviceEntity> availableDevices,  bool llmCloudAllowed,  LlmProviderId? llmPreferred,  LlmProviderId llmActive,  Map<LlmProviderId, String> llmModels,  Map<LlmProviderId, String> llmKeySuffixes,  Set<LlmProviderId> llmKeyErrors,  Map<LlmProviderId, LlmTestStatus> llmTests)?  $default,) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.selectedMicId,_that.systemAudioEnabled,_that.autoStartServer,_that.serverPort,_that.storagePath,_that.dbSizeMb,_that.availableDevices,_that.llmCloudAllowed,_that.llmPreferred,_that.llmActive,_that.llmModels,_that.llmKeySuffixes,_that.llmKeyErrors,_that.llmTests);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsState implements SettingsState {
  const _SettingsState({this.selectedMicId, this.systemAudioEnabled = true, this.autoStartServer = true, this.serverPort = '8000', this.storagePath = '', this.dbSizeMb = 0.0, required final  List<AudioDeviceEntity> availableDevices, this.llmCloudAllowed = false, this.llmPreferred, this.llmActive = LlmProviderId.ollama, final  Map<LlmProviderId, String> llmModels = const <LlmProviderId, String>{}, final  Map<LlmProviderId, String> llmKeySuffixes = const <LlmProviderId, String>{}, final  Set<LlmProviderId> llmKeyErrors = const <LlmProviderId>{}, final  Map<LlmProviderId, LlmTestStatus> llmTests = const <LlmProviderId, LlmTestStatus>{}}): _availableDevices = availableDevices,_llmModels = llmModels,_llmKeySuffixes = llmKeySuffixes,_llmKeyErrors = llmKeyErrors,_llmTests = llmTests;
  

/// Identifiant du microphone selectionne.
@override final  String? selectedMicId;
/// Indique si la capture audio systeme est activee.
@override@JsonKey() final  bool systemAudioEnabled;
/// Indique si le serveur ML doit demarrer automatiquement.
@override@JsonKey() final  bool autoStartServer;
/// Port du serveur ML (voxmlx-serve default: 8000).
@override@JsonKey() final  String serverPort;
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

/// Envoi à un service LLM en ligne autorisé (coupé par défaut).
@override@JsonKey() final  bool llmCloudAllowed;
/// Fournisseur LLM choisi ; null = repli automatique.
@override final  LlmProviderId? llmPreferred;
/// Fournisseur LLM réellement utilisé (choix, autorisation et clés).
@override@JsonKey() final  LlmProviderId llmActive;
/// Modèles choisis par fournisseur ; absent = modèle par défaut.
 final  Map<LlmProviderId, String> _llmModels;
/// Modèles choisis par fournisseur ; absent = modèle par défaut.
@override@JsonKey() Map<LlmProviderId, String> get llmModels {
  if (_llmModels is EqualUnmodifiableMapView) return _llmModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_llmModels);
}

/// 4 derniers caractères de chaque clé rangée (jamais la clé entière).
 final  Map<LlmProviderId, String> _llmKeySuffixes;
/// 4 derniers caractères de chaque clé rangée (jamais la clé entière).
@override@JsonKey() Map<LlmProviderId, String> get llmKeySuffixes {
  if (_llmKeySuffixes is EqualUnmodifiableMapView) return _llmKeySuffixes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_llmKeySuffixes);
}

/// Fournisseurs dont le trousseau a refusé la lecture ou l'écriture.
 final  Set<LlmProviderId> _llmKeyErrors;
/// Fournisseurs dont le trousseau a refusé la lecture ou l'écriture.
@override@JsonKey() Set<LlmProviderId> get llmKeyErrors {
  if (_llmKeyErrors is EqualUnmodifiableSetView) return _llmKeyErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_llmKeyErrors);
}

/// Dernier résultat de « Tester » par fournisseur.
 final  Map<LlmProviderId, LlmTestStatus> _llmTests;
/// Dernier résultat de « Tester » par fournisseur.
@override@JsonKey() Map<LlmProviderId, LlmTestStatus> get llmTests {
  if (_llmTests is EqualUnmodifiableMapView) return _llmTests;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_llmTests);
}


/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsStateCopyWith<_SettingsState> get copyWith => __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsState&&(identical(other.selectedMicId, selectedMicId) || other.selectedMicId == selectedMicId)&&(identical(other.systemAudioEnabled, systemAudioEnabled) || other.systemAudioEnabled == systemAudioEnabled)&&(identical(other.autoStartServer, autoStartServer) || other.autoStartServer == autoStartServer)&&(identical(other.serverPort, serverPort) || other.serverPort == serverPort)&&(identical(other.storagePath, storagePath) || other.storagePath == storagePath)&&(identical(other.dbSizeMb, dbSizeMb) || other.dbSizeMb == dbSizeMb)&&const DeepCollectionEquality().equals(other._availableDevices, _availableDevices)&&(identical(other.llmCloudAllowed, llmCloudAllowed) || other.llmCloudAllowed == llmCloudAllowed)&&(identical(other.llmPreferred, llmPreferred) || other.llmPreferred == llmPreferred)&&(identical(other.llmActive, llmActive) || other.llmActive == llmActive)&&const DeepCollectionEquality().equals(other._llmModels, _llmModels)&&const DeepCollectionEquality().equals(other._llmKeySuffixes, _llmKeySuffixes)&&const DeepCollectionEquality().equals(other._llmKeyErrors, _llmKeyErrors)&&const DeepCollectionEquality().equals(other._llmTests, _llmTests));
}


@override
int get hashCode => Object.hash(runtimeType,selectedMicId,systemAudioEnabled,autoStartServer,serverPort,storagePath,dbSizeMb,const DeepCollectionEquality().hash(_availableDevices),llmCloudAllowed,llmPreferred,llmActive,const DeepCollectionEquality().hash(_llmModels),const DeepCollectionEquality().hash(_llmKeySuffixes),const DeepCollectionEquality().hash(_llmKeyErrors),const DeepCollectionEquality().hash(_llmTests));

@override
String toString() {
  return 'SettingsState(selectedMicId: $selectedMicId, systemAudioEnabled: $systemAudioEnabled, autoStartServer: $autoStartServer, serverPort: $serverPort, storagePath: $storagePath, dbSizeMb: $dbSizeMb, availableDevices: $availableDevices, llmCloudAllowed: $llmCloudAllowed, llmPreferred: $llmPreferred, llmActive: $llmActive, llmModels: $llmModels, llmKeySuffixes: $llmKeySuffixes, llmKeyErrors: $llmKeyErrors, llmTests: $llmTests)';
}


}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res> implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(_SettingsState value, $Res Function(_SettingsState) _then) = __$SettingsStateCopyWithImpl;
@override @useResult
$Res call({
 String? selectedMicId, bool systemAudioEnabled, bool autoStartServer, String serverPort, String storagePath, double dbSizeMb, List<AudioDeviceEntity> availableDevices, bool llmCloudAllowed, LlmProviderId? llmPreferred, LlmProviderId llmActive, Map<LlmProviderId, String> llmModels, Map<LlmProviderId, String> llmKeySuffixes, Set<LlmProviderId> llmKeyErrors, Map<LlmProviderId, LlmTestStatus> llmTests
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
@override @pragma('vm:prefer-inline') $Res call({Object? selectedMicId = freezed,Object? systemAudioEnabled = null,Object? autoStartServer = null,Object? serverPort = null,Object? storagePath = null,Object? dbSizeMb = null,Object? availableDevices = null,Object? llmCloudAllowed = null,Object? llmPreferred = freezed,Object? llmActive = null,Object? llmModels = null,Object? llmKeySuffixes = null,Object? llmKeyErrors = null,Object? llmTests = null,}) {
  return _then(_SettingsState(
selectedMicId: freezed == selectedMicId ? _self.selectedMicId : selectedMicId // ignore: cast_nullable_to_non_nullable
as String?,systemAudioEnabled: null == systemAudioEnabled ? _self.systemAudioEnabled : systemAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoStartServer: null == autoStartServer ? _self.autoStartServer : autoStartServer // ignore: cast_nullable_to_non_nullable
as bool,serverPort: null == serverPort ? _self.serverPort : serverPort // ignore: cast_nullable_to_non_nullable
as String,storagePath: null == storagePath ? _self.storagePath : storagePath // ignore: cast_nullable_to_non_nullable
as String,dbSizeMb: null == dbSizeMb ? _self.dbSizeMb : dbSizeMb // ignore: cast_nullable_to_non_nullable
as double,availableDevices: null == availableDevices ? _self._availableDevices : availableDevices // ignore: cast_nullable_to_non_nullable
as List<AudioDeviceEntity>,llmCloudAllowed: null == llmCloudAllowed ? _self.llmCloudAllowed : llmCloudAllowed // ignore: cast_nullable_to_non_nullable
as bool,llmPreferred: freezed == llmPreferred ? _self.llmPreferred : llmPreferred // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,llmActive: null == llmActive ? _self.llmActive : llmActive // ignore: cast_nullable_to_non_nullable
as LlmProviderId,llmModels: null == llmModels ? _self._llmModels : llmModels // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, String>,llmKeySuffixes: null == llmKeySuffixes ? _self._llmKeySuffixes : llmKeySuffixes // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, String>,llmKeyErrors: null == llmKeyErrors ? _self._llmKeyErrors : llmKeyErrors // ignore: cast_nullable_to_non_nullable
as Set<LlmProviderId>,llmTests: null == llmTests ? _self._llmTests : llmTests // ignore: cast_nullable_to_non_nullable
as Map<LlmProviderId, LlmTestStatus>,
  ));
}


}

// dart format on
