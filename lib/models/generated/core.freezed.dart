// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../core.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SetupParams {

@JsonKey(name: 'selected-map') Map<String, String> get selectedMap;@JsonKey(name: 'test-url') String get testUrl;
/// Create a copy of SetupParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetupParamsCopyWith<SetupParams> get copyWith => _$SetupParamsCopyWithImpl<SetupParams>(this as SetupParams, _$identity);

  /// Serializes this SetupParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetupParams&&const DeepCollectionEquality().equals(other.selectedMap, selectedMap)&&(identical(other.testUrl, testUrl) || other.testUrl == testUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(selectedMap),testUrl);

@override
String toString() {
  return 'SetupParams(selectedMap: $selectedMap, testUrl: $testUrl)';
}


}

/// @nodoc
abstract mixin class $SetupParamsCopyWith<$Res>  {
  factory $SetupParamsCopyWith(SetupParams value, $Res Function(SetupParams) _then) = _$SetupParamsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'selected-map') Map<String, String> selectedMap,@JsonKey(name: 'test-url') String testUrl
});




}
/// @nodoc
class _$SetupParamsCopyWithImpl<$Res>
    implements $SetupParamsCopyWith<$Res> {
  _$SetupParamsCopyWithImpl(this._self, this._then);

  final SetupParams _self;
  final $Res Function(SetupParams) _then;

/// Create a copy of SetupParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedMap = null,Object? testUrl = null,}) {
  return _then(_self.copyWith(
selectedMap: null == selectedMap ? _self.selectedMap : selectedMap // ignore: cast_nullable_to_non_nullable
as Map<String, String>,testUrl: null == testUrl ? _self.testUrl : testUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SetupParams].
extension SetupParamsPatterns on SetupParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetupParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetupParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetupParams value)  $default,){
final _that = this;
switch (_that) {
case _SetupParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetupParams value)?  $default,){
final _that = this;
switch (_that) {
case _SetupParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'selected-map')  Map<String, String> selectedMap, @JsonKey(name: 'test-url')  String testUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetupParams() when $default != null:
return $default(_that.selectedMap,_that.testUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'selected-map')  Map<String, String> selectedMap, @JsonKey(name: 'test-url')  String testUrl)  $default,) {final _that = this;
switch (_that) {
case _SetupParams():
return $default(_that.selectedMap,_that.testUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'selected-map')  Map<String, String> selectedMap, @JsonKey(name: 'test-url')  String testUrl)?  $default,) {final _that = this;
switch (_that) {
case _SetupParams() when $default != null:
return $default(_that.selectedMap,_that.testUrl);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SetupParams implements SetupParams {
  const _SetupParams({@JsonKey(name: 'selected-map') required final  Map<String, String> selectedMap, @JsonKey(name: 'test-url') required this.testUrl}): _selectedMap = selectedMap;
  factory _SetupParams.fromJson(Map<String, dynamic> json) => _$SetupParamsFromJson(json);

 final  Map<String, String> _selectedMap;
@override@JsonKey(name: 'selected-map') Map<String, String> get selectedMap {
  if (_selectedMap is EqualUnmodifiableMapView) return _selectedMap;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_selectedMap);
}

@override@JsonKey(name: 'test-url') final  String testUrl;

/// Create a copy of SetupParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetupParamsCopyWith<_SetupParams> get copyWith => __$SetupParamsCopyWithImpl<_SetupParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SetupParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetupParams&&const DeepCollectionEquality().equals(other._selectedMap, _selectedMap)&&(identical(other.testUrl, testUrl) || other.testUrl == testUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_selectedMap),testUrl);

@override
String toString() {
  return 'SetupParams(selectedMap: $selectedMap, testUrl: $testUrl)';
}


}

/// @nodoc
abstract mixin class _$SetupParamsCopyWith<$Res> implements $SetupParamsCopyWith<$Res> {
  factory _$SetupParamsCopyWith(_SetupParams value, $Res Function(_SetupParams) _then) = __$SetupParamsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'selected-map') Map<String, String> selectedMap,@JsonKey(name: 'test-url') String testUrl
});




}
/// @nodoc
class __$SetupParamsCopyWithImpl<$Res>
    implements _$SetupParamsCopyWith<$Res> {
  __$SetupParamsCopyWithImpl(this._self, this._then);

  final _SetupParams _self;
  final $Res Function(_SetupParams) _then;

/// Create a copy of SetupParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedMap = null,Object? testUrl = null,}) {
  return _then(_SetupParams(
selectedMap: null == selectedMap ? _self._selectedMap : selectedMap // ignore: cast_nullable_to_non_nullable
as Map<String, String>,testUrl: null == testUrl ? _self.testUrl : testUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$UpdateParams {

 Tun get tun;@JsonKey(name: 'mixed-port') int get mixedPort;@JsonKey(name: 'allow-lan') bool get allowLan;@JsonKey(name: 'find-process-mode') FindProcessMode get findProcessMode; Mode get mode;@JsonKey(name: 'log-level') LogLevel get logLevel; bool get ipv6;@JsonKey(name: 'tcp-concurrent') bool get tcpConcurrent;@JsonKey(name: 'external-controller') ExternalControllerStatus get externalController;@JsonKey(name: 'unified-delay') bool get unifiedDelay;@JsonKey(name: 'geo-auto-update') bool get geoAutoUpdate;@JsonKey(name: 'geo-update-interval') int get geoUpdateInterval;
/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateParamsCopyWith<UpdateParams> get copyWith => _$UpdateParamsCopyWithImpl<UpdateParams>(this as UpdateParams, _$identity);

  /// Serializes this UpdateParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateParams&&(identical(other.tun, tun) || other.tun == tun)&&(identical(other.mixedPort, mixedPort) || other.mixedPort == mixedPort)&&(identical(other.allowLan, allowLan) || other.allowLan == allowLan)&&(identical(other.findProcessMode, findProcessMode) || other.findProcessMode == findProcessMode)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel)&&(identical(other.ipv6, ipv6) || other.ipv6 == ipv6)&&(identical(other.tcpConcurrent, tcpConcurrent) || other.tcpConcurrent == tcpConcurrent)&&(identical(other.externalController, externalController) || other.externalController == externalController)&&(identical(other.unifiedDelay, unifiedDelay) || other.unifiedDelay == unifiedDelay)&&(identical(other.geoAutoUpdate, geoAutoUpdate) || other.geoAutoUpdate == geoAutoUpdate)&&(identical(other.geoUpdateInterval, geoUpdateInterval) || other.geoUpdateInterval == geoUpdateInterval));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,tun,mixedPort,allowLan,findProcessMode,mode,logLevel,ipv6,tcpConcurrent,externalController,unifiedDelay,geoAutoUpdate,geoUpdateInterval);

@override
String toString() {
  return 'UpdateParams(tun: $tun, mixedPort: $mixedPort, allowLan: $allowLan, findProcessMode: $findProcessMode, mode: $mode, logLevel: $logLevel, ipv6: $ipv6, tcpConcurrent: $tcpConcurrent, externalController: $externalController, unifiedDelay: $unifiedDelay, geoAutoUpdate: $geoAutoUpdate, geoUpdateInterval: $geoUpdateInterval)';
}


}

/// @nodoc
abstract mixin class $UpdateParamsCopyWith<$Res>  {
  factory $UpdateParamsCopyWith(UpdateParams value, $Res Function(UpdateParams) _then) = _$UpdateParamsCopyWithImpl;
@useResult
$Res call({
 Tun tun,@JsonKey(name: 'mixed-port') int mixedPort,@JsonKey(name: 'allow-lan') bool allowLan,@JsonKey(name: 'find-process-mode') FindProcessMode findProcessMode, Mode mode,@JsonKey(name: 'log-level') LogLevel logLevel, bool ipv6,@JsonKey(name: 'tcp-concurrent') bool tcpConcurrent,@JsonKey(name: 'external-controller') ExternalControllerStatus externalController,@JsonKey(name: 'unified-delay') bool unifiedDelay,@JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,@JsonKey(name: 'geo-update-interval') int geoUpdateInterval
});


$TunCopyWith<$Res> get tun;

}
/// @nodoc
class _$UpdateParamsCopyWithImpl<$Res>
    implements $UpdateParamsCopyWith<$Res> {
  _$UpdateParamsCopyWithImpl(this._self, this._then);

  final UpdateParams _self;
  final $Res Function(UpdateParams) _then;

/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tun = null,Object? mixedPort = null,Object? allowLan = null,Object? findProcessMode = null,Object? mode = null,Object? logLevel = null,Object? ipv6 = null,Object? tcpConcurrent = null,Object? externalController = null,Object? unifiedDelay = null,Object? geoAutoUpdate = null,Object? geoUpdateInterval = null,}) {
  return _then(_self.copyWith(
tun: null == tun ? _self.tun : tun // ignore: cast_nullable_to_non_nullable
as Tun,mixedPort: null == mixedPort ? _self.mixedPort : mixedPort // ignore: cast_nullable_to_non_nullable
as int,allowLan: null == allowLan ? _self.allowLan : allowLan // ignore: cast_nullable_to_non_nullable
as bool,findProcessMode: null == findProcessMode ? _self.findProcessMode : findProcessMode // ignore: cast_nullable_to_non_nullable
as FindProcessMode,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as Mode,logLevel: null == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as LogLevel,ipv6: null == ipv6 ? _self.ipv6 : ipv6 // ignore: cast_nullable_to_non_nullable
as bool,tcpConcurrent: null == tcpConcurrent ? _self.tcpConcurrent : tcpConcurrent // ignore: cast_nullable_to_non_nullable
as bool,externalController: null == externalController ? _self.externalController : externalController // ignore: cast_nullable_to_non_nullable
as ExternalControllerStatus,unifiedDelay: null == unifiedDelay ? _self.unifiedDelay : unifiedDelay // ignore: cast_nullable_to_non_nullable
as bool,geoAutoUpdate: null == geoAutoUpdate ? _self.geoAutoUpdate : geoAutoUpdate // ignore: cast_nullable_to_non_nullable
as bool,geoUpdateInterval: null == geoUpdateInterval ? _self.geoUpdateInterval : geoUpdateInterval // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TunCopyWith<$Res> get tun {

  return $TunCopyWith<$Res>(_self.tun, (value) {
    return _then(_self.copyWith(tun: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateParams].
extension UpdateParamsPatterns on UpdateParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateParams value)  $default,){
final _that = this;
switch (_that) {
case _UpdateParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateParams value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Tun tun, @JsonKey(name: 'mixed-port')  int mixedPort, @JsonKey(name: 'allow-lan')  bool allowLan, @JsonKey(name: 'find-process-mode')  FindProcessMode findProcessMode,  Mode mode, @JsonKey(name: 'log-level')  LogLevel logLevel,  bool ipv6, @JsonKey(name: 'tcp-concurrent')  bool tcpConcurrent, @JsonKey(name: 'external-controller')  ExternalControllerStatus externalController, @JsonKey(name: 'unified-delay')  bool unifiedDelay, @JsonKey(name: 'geo-auto-update')  bool geoAutoUpdate, @JsonKey(name: 'geo-update-interval')  int geoUpdateInterval)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateParams() when $default != null:
return $default(_that.tun,_that.mixedPort,_that.allowLan,_that.findProcessMode,_that.mode,_that.logLevel,_that.ipv6,_that.tcpConcurrent,_that.externalController,_that.unifiedDelay,_that.geoAutoUpdate,_that.geoUpdateInterval);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Tun tun, @JsonKey(name: 'mixed-port')  int mixedPort, @JsonKey(name: 'allow-lan')  bool allowLan, @JsonKey(name: 'find-process-mode')  FindProcessMode findProcessMode,  Mode mode, @JsonKey(name: 'log-level')  LogLevel logLevel,  bool ipv6, @JsonKey(name: 'tcp-concurrent')  bool tcpConcurrent, @JsonKey(name: 'external-controller')  ExternalControllerStatus externalController, @JsonKey(name: 'unified-delay')  bool unifiedDelay, @JsonKey(name: 'geo-auto-update')  bool geoAutoUpdate, @JsonKey(name: 'geo-update-interval')  int geoUpdateInterval)  $default,) {final _that = this;
switch (_that) {
case _UpdateParams():
return $default(_that.tun,_that.mixedPort,_that.allowLan,_that.findProcessMode,_that.mode,_that.logLevel,_that.ipv6,_that.tcpConcurrent,_that.externalController,_that.unifiedDelay,_that.geoAutoUpdate,_that.geoUpdateInterval);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Tun tun, @JsonKey(name: 'mixed-port')  int mixedPort, @JsonKey(name: 'allow-lan')  bool allowLan, @JsonKey(name: 'find-process-mode')  FindProcessMode findProcessMode,  Mode mode, @JsonKey(name: 'log-level')  LogLevel logLevel,  bool ipv6, @JsonKey(name: 'tcp-concurrent')  bool tcpConcurrent, @JsonKey(name: 'external-controller')  ExternalControllerStatus externalController, @JsonKey(name: 'unified-delay')  bool unifiedDelay, @JsonKey(name: 'geo-auto-update')  bool geoAutoUpdate, @JsonKey(name: 'geo-update-interval')  int geoUpdateInterval)?  $default,) {final _that = this;
switch (_that) {
case _UpdateParams() when $default != null:
return $default(_that.tun,_that.mixedPort,_that.allowLan,_that.findProcessMode,_that.mode,_that.logLevel,_that.ipv6,_that.tcpConcurrent,_that.externalController,_that.unifiedDelay,_that.geoAutoUpdate,_that.geoUpdateInterval);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UpdateParams implements UpdateParams {
  const _UpdateParams({required this.tun, @JsonKey(name: 'mixed-port') required this.mixedPort, @JsonKey(name: 'allow-lan') required this.allowLan, @JsonKey(name: 'find-process-mode') required this.findProcessMode, required this.mode, @JsonKey(name: 'log-level') required this.logLevel, required this.ipv6, @JsonKey(name: 'tcp-concurrent') required this.tcpConcurrent, @JsonKey(name: 'external-controller') required this.externalController, @JsonKey(name: 'unified-delay') required this.unifiedDelay, @JsonKey(name: 'geo-auto-update') this.geoAutoUpdate = false, @JsonKey(name: 'geo-update-interval') this.geoUpdateInterval = 24});
  factory _UpdateParams.fromJson(Map<String, dynamic> json) => _$UpdateParamsFromJson(json);

@override final  Tun tun;
@override@JsonKey(name: 'mixed-port') final  int mixedPort;
@override@JsonKey(name: 'allow-lan') final  bool allowLan;
@override@JsonKey(name: 'find-process-mode') final  FindProcessMode findProcessMode;
@override final  Mode mode;
@override@JsonKey(name: 'log-level') final  LogLevel logLevel;
@override final  bool ipv6;
@override@JsonKey(name: 'tcp-concurrent') final  bool tcpConcurrent;
@override@JsonKey(name: 'external-controller') final  ExternalControllerStatus externalController;
@override@JsonKey(name: 'unified-delay') final  bool unifiedDelay;
@override@JsonKey(name: 'geo-auto-update') final  bool geoAutoUpdate;
@override@JsonKey(name: 'geo-update-interval') final  int geoUpdateInterval;

/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateParamsCopyWith<_UpdateParams> get copyWith => __$UpdateParamsCopyWithImpl<_UpdateParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UpdateParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateParams&&(identical(other.tun, tun) || other.tun == tun)&&(identical(other.mixedPort, mixedPort) || other.mixedPort == mixedPort)&&(identical(other.allowLan, allowLan) || other.allowLan == allowLan)&&(identical(other.findProcessMode, findProcessMode) || other.findProcessMode == findProcessMode)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel)&&(identical(other.ipv6, ipv6) || other.ipv6 == ipv6)&&(identical(other.tcpConcurrent, tcpConcurrent) || other.tcpConcurrent == tcpConcurrent)&&(identical(other.externalController, externalController) || other.externalController == externalController)&&(identical(other.unifiedDelay, unifiedDelay) || other.unifiedDelay == unifiedDelay)&&(identical(other.geoAutoUpdate, geoAutoUpdate) || other.geoAutoUpdate == geoAutoUpdate)&&(identical(other.geoUpdateInterval, geoUpdateInterval) || other.geoUpdateInterval == geoUpdateInterval));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,tun,mixedPort,allowLan,findProcessMode,mode,logLevel,ipv6,tcpConcurrent,externalController,unifiedDelay,geoAutoUpdate,geoUpdateInterval);

@override
String toString() {
  return 'UpdateParams(tun: $tun, mixedPort: $mixedPort, allowLan: $allowLan, findProcessMode: $findProcessMode, mode: $mode, logLevel: $logLevel, ipv6: $ipv6, tcpConcurrent: $tcpConcurrent, externalController: $externalController, unifiedDelay: $unifiedDelay, geoAutoUpdate: $geoAutoUpdate, geoUpdateInterval: $geoUpdateInterval)';
}


}

/// @nodoc
abstract mixin class _$UpdateParamsCopyWith<$Res> implements $UpdateParamsCopyWith<$Res> {
  factory _$UpdateParamsCopyWith(_UpdateParams value, $Res Function(_UpdateParams) _then) = __$UpdateParamsCopyWithImpl;
@override @useResult
$Res call({
 Tun tun,@JsonKey(name: 'mixed-port') int mixedPort,@JsonKey(name: 'allow-lan') bool allowLan,@JsonKey(name: 'find-process-mode') FindProcessMode findProcessMode, Mode mode,@JsonKey(name: 'log-level') LogLevel logLevel, bool ipv6,@JsonKey(name: 'tcp-concurrent') bool tcpConcurrent,@JsonKey(name: 'external-controller') ExternalControllerStatus externalController,@JsonKey(name: 'unified-delay') bool unifiedDelay,@JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,@JsonKey(name: 'geo-update-interval') int geoUpdateInterval
});


@override $TunCopyWith<$Res> get tun;

}
/// @nodoc
class __$UpdateParamsCopyWithImpl<$Res>
    implements _$UpdateParamsCopyWith<$Res> {
  __$UpdateParamsCopyWithImpl(this._self, this._then);

  final _UpdateParams _self;
  final $Res Function(_UpdateParams) _then;

/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tun = null,Object? mixedPort = null,Object? allowLan = null,Object? findProcessMode = null,Object? mode = null,Object? logLevel = null,Object? ipv6 = null,Object? tcpConcurrent = null,Object? externalController = null,Object? unifiedDelay = null,Object? geoAutoUpdate = null,Object? geoUpdateInterval = null,}) {
  return _then(_UpdateParams(
tun: null == tun ? _self.tun : tun // ignore: cast_nullable_to_non_nullable
as Tun,mixedPort: null == mixedPort ? _self.mixedPort : mixedPort // ignore: cast_nullable_to_non_nullable
as int,allowLan: null == allowLan ? _self.allowLan : allowLan // ignore: cast_nullable_to_non_nullable
as bool,findProcessMode: null == findProcessMode ? _self.findProcessMode : findProcessMode // ignore: cast_nullable_to_non_nullable
as FindProcessMode,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as Mode,logLevel: null == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as LogLevel,ipv6: null == ipv6 ? _self.ipv6 : ipv6 // ignore: cast_nullable_to_non_nullable
as bool,tcpConcurrent: null == tcpConcurrent ? _self.tcpConcurrent : tcpConcurrent // ignore: cast_nullable_to_non_nullable
as bool,externalController: null == externalController ? _self.externalController : externalController // ignore: cast_nullable_to_non_nullable
as ExternalControllerStatus,unifiedDelay: null == unifiedDelay ? _self.unifiedDelay : unifiedDelay // ignore: cast_nullable_to_non_nullable
as bool,geoAutoUpdate: null == geoAutoUpdate ? _self.geoAutoUpdate : geoAutoUpdate // ignore: cast_nullable_to_non_nullable
as bool,geoUpdateInterval: null == geoUpdateInterval ? _self.geoUpdateInterval : geoUpdateInterval // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdateParams
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TunCopyWith<$Res> get tun {

  return $TunCopyWith<$Res>(_self.tun, (value) {
    return _then(_self.copyWith(tun: value));
  });
}
}


/// @nodoc
mixin _$VpnOptions {

 bool get enable; int get port; bool get ipv6; bool get dnsHijacking; AccessControlProps get accessControlProps; bool get allowBypass; bool get systemProxy; List<String> get bypassDomain; String get stack; List<String> get routeAddress;
/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VpnOptionsCopyWith<VpnOptions> get copyWith => _$VpnOptionsCopyWithImpl<VpnOptions>(this as VpnOptions, _$identity);

  /// Serializes this VpnOptions to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VpnOptions&&(identical(other.enable, enable) || other.enable == enable)&&(identical(other.port, port) || other.port == port)&&(identical(other.ipv6, ipv6) || other.ipv6 == ipv6)&&(identical(other.dnsHijacking, dnsHijacking) || other.dnsHijacking == dnsHijacking)&&(identical(other.accessControlProps, accessControlProps) || other.accessControlProps == accessControlProps)&&(identical(other.allowBypass, allowBypass) || other.allowBypass == allowBypass)&&(identical(other.systemProxy, systemProxy) || other.systemProxy == systemProxy)&&const DeepCollectionEquality().equals(other.bypassDomain, bypassDomain)&&(identical(other.stack, stack) || other.stack == stack)&&const DeepCollectionEquality().equals(other.routeAddress, routeAddress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,enable,port,ipv6,dnsHijacking,accessControlProps,allowBypass,systemProxy,const DeepCollectionEquality().hash(bypassDomain),stack,const DeepCollectionEquality().hash(routeAddress));

@override
String toString() {
  return 'VpnOptions(enable: $enable, port: $port, ipv6: $ipv6, dnsHijacking: $dnsHijacking, accessControlProps: $accessControlProps, allowBypass: $allowBypass, systemProxy: $systemProxy, bypassDomain: $bypassDomain, stack: $stack, routeAddress: $routeAddress)';
}


}

/// @nodoc
abstract mixin class $VpnOptionsCopyWith<$Res>  {
  factory $VpnOptionsCopyWith(VpnOptions value, $Res Function(VpnOptions) _then) = _$VpnOptionsCopyWithImpl;
@useResult
$Res call({
 bool enable, int port, bool ipv6, bool dnsHijacking, AccessControlProps accessControlProps, bool allowBypass, bool systemProxy, List<String> bypassDomain, String stack, List<String> routeAddress
});


$AccessControlPropsCopyWith<$Res> get accessControlProps;

}
/// @nodoc
class _$VpnOptionsCopyWithImpl<$Res>
    implements $VpnOptionsCopyWith<$Res> {
  _$VpnOptionsCopyWithImpl(this._self, this._then);

  final VpnOptions _self;
  final $Res Function(VpnOptions) _then;

/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enable = null,Object? port = null,Object? ipv6 = null,Object? dnsHijacking = null,Object? accessControlProps = null,Object? allowBypass = null,Object? systemProxy = null,Object? bypassDomain = null,Object? stack = null,Object? routeAddress = null,}) {
  return _then(_self.copyWith(
enable: null == enable ? _self.enable : enable // ignore: cast_nullable_to_non_nullable
as bool,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,ipv6: null == ipv6 ? _self.ipv6 : ipv6 // ignore: cast_nullable_to_non_nullable
as bool,dnsHijacking: null == dnsHijacking ? _self.dnsHijacking : dnsHijacking // ignore: cast_nullable_to_non_nullable
as bool,accessControlProps: null == accessControlProps ? _self.accessControlProps : accessControlProps // ignore: cast_nullable_to_non_nullable
as AccessControlProps,allowBypass: null == allowBypass ? _self.allowBypass : allowBypass // ignore: cast_nullable_to_non_nullable
as bool,systemProxy: null == systemProxy ? _self.systemProxy : systemProxy // ignore: cast_nullable_to_non_nullable
as bool,bypassDomain: null == bypassDomain ? _self.bypassDomain : bypassDomain // ignore: cast_nullable_to_non_nullable
as List<String>,stack: null == stack ? _self.stack : stack // ignore: cast_nullable_to_non_nullable
as String,routeAddress: null == routeAddress ? _self.routeAddress : routeAddress // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}
/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccessControlPropsCopyWith<$Res> get accessControlProps {

  return $AccessControlPropsCopyWith<$Res>(_self.accessControlProps, (value) {
    return _then(_self.copyWith(accessControlProps: value));
  });
}
}


/// Adds pattern-matching-related methods to [VpnOptions].
extension VpnOptionsPatterns on VpnOptions {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VpnOptions value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VpnOptions() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VpnOptions value)  $default,){
final _that = this;
switch (_that) {
case _VpnOptions():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VpnOptions value)?  $default,){
final _that = this;
switch (_that) {
case _VpnOptions() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enable,  int port,  bool ipv6,  bool dnsHijacking,  AccessControlProps accessControlProps,  bool allowBypass,  bool systemProxy,  List<String> bypassDomain,  String stack,  List<String> routeAddress)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VpnOptions() when $default != null:
return $default(_that.enable,_that.port,_that.ipv6,_that.dnsHijacking,_that.accessControlProps,_that.allowBypass,_that.systemProxy,_that.bypassDomain,_that.stack,_that.routeAddress);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enable,  int port,  bool ipv6,  bool dnsHijacking,  AccessControlProps accessControlProps,  bool allowBypass,  bool systemProxy,  List<String> bypassDomain,  String stack,  List<String> routeAddress)  $default,) {final _that = this;
switch (_that) {
case _VpnOptions():
return $default(_that.enable,_that.port,_that.ipv6,_that.dnsHijacking,_that.accessControlProps,_that.allowBypass,_that.systemProxy,_that.bypassDomain,_that.stack,_that.routeAddress);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enable,  int port,  bool ipv6,  bool dnsHijacking,  AccessControlProps accessControlProps,  bool allowBypass,  bool systemProxy,  List<String> bypassDomain,  String stack,  List<String> routeAddress)?  $default,) {final _that = this;
switch (_that) {
case _VpnOptions() when $default != null:
return $default(_that.enable,_that.port,_that.ipv6,_that.dnsHijacking,_that.accessControlProps,_that.allowBypass,_that.systemProxy,_that.bypassDomain,_that.stack,_that.routeAddress);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _VpnOptions implements VpnOptions {
  const _VpnOptions({required this.enable, required this.port, required this.ipv6, required this.dnsHijacking, required this.accessControlProps, required this.allowBypass, required this.systemProxy, required final  List<String> bypassDomain, required this.stack, final  List<String> routeAddress = const []}): _bypassDomain = bypassDomain,_routeAddress = routeAddress;
  factory _VpnOptions.fromJson(Map<String, dynamic> json) => _$VpnOptionsFromJson(json);

@override final  bool enable;
@override final  int port;
@override final  bool ipv6;
@override final  bool dnsHijacking;
@override final  AccessControlProps accessControlProps;
@override final  bool allowBypass;
@override final  bool systemProxy;
 final  List<String> _bypassDomain;
@override List<String> get bypassDomain {
  if (_bypassDomain is EqualUnmodifiableListView) return _bypassDomain;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bypassDomain);
}

@override final  String stack;
 final  List<String> _routeAddress;
@override@JsonKey() List<String> get routeAddress {
  if (_routeAddress is EqualUnmodifiableListView) return _routeAddress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_routeAddress);
}


/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VpnOptionsCopyWith<_VpnOptions> get copyWith => __$VpnOptionsCopyWithImpl<_VpnOptions>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VpnOptionsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VpnOptions&&(identical(other.enable, enable) || other.enable == enable)&&(identical(other.port, port) || other.port == port)&&(identical(other.ipv6, ipv6) || other.ipv6 == ipv6)&&(identical(other.dnsHijacking, dnsHijacking) || other.dnsHijacking == dnsHijacking)&&(identical(other.accessControlProps, accessControlProps) || other.accessControlProps == accessControlProps)&&(identical(other.allowBypass, allowBypass) || other.allowBypass == allowBypass)&&(identical(other.systemProxy, systemProxy) || other.systemProxy == systemProxy)&&const DeepCollectionEquality().equals(other._bypassDomain, _bypassDomain)&&(identical(other.stack, stack) || other.stack == stack)&&const DeepCollectionEquality().equals(other._routeAddress, _routeAddress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,enable,port,ipv6,dnsHijacking,accessControlProps,allowBypass,systemProxy,const DeepCollectionEquality().hash(_bypassDomain),stack,const DeepCollectionEquality().hash(_routeAddress));

@override
String toString() {
  return 'VpnOptions(enable: $enable, port: $port, ipv6: $ipv6, dnsHijacking: $dnsHijacking, accessControlProps: $accessControlProps, allowBypass: $allowBypass, systemProxy: $systemProxy, bypassDomain: $bypassDomain, stack: $stack, routeAddress: $routeAddress)';
}


}

/// @nodoc
abstract mixin class _$VpnOptionsCopyWith<$Res> implements $VpnOptionsCopyWith<$Res> {
  factory _$VpnOptionsCopyWith(_VpnOptions value, $Res Function(_VpnOptions) _then) = __$VpnOptionsCopyWithImpl;
@override @useResult
$Res call({
 bool enable, int port, bool ipv6, bool dnsHijacking, AccessControlProps accessControlProps, bool allowBypass, bool systemProxy, List<String> bypassDomain, String stack, List<String> routeAddress
});


@override $AccessControlPropsCopyWith<$Res> get accessControlProps;

}
/// @nodoc
class __$VpnOptionsCopyWithImpl<$Res>
    implements _$VpnOptionsCopyWith<$Res> {
  __$VpnOptionsCopyWithImpl(this._self, this._then);

  final _VpnOptions _self;
  final $Res Function(_VpnOptions) _then;

/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enable = null,Object? port = null,Object? ipv6 = null,Object? dnsHijacking = null,Object? accessControlProps = null,Object? allowBypass = null,Object? systemProxy = null,Object? bypassDomain = null,Object? stack = null,Object? routeAddress = null,}) {
  return _then(_VpnOptions(
enable: null == enable ? _self.enable : enable // ignore: cast_nullable_to_non_nullable
as bool,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,ipv6: null == ipv6 ? _self.ipv6 : ipv6 // ignore: cast_nullable_to_non_nullable
as bool,dnsHijacking: null == dnsHijacking ? _self.dnsHijacking : dnsHijacking // ignore: cast_nullable_to_non_nullable
as bool,accessControlProps: null == accessControlProps ? _self.accessControlProps : accessControlProps // ignore: cast_nullable_to_non_nullable
as AccessControlProps,allowBypass: null == allowBypass ? _self.allowBypass : allowBypass // ignore: cast_nullable_to_non_nullable
as bool,systemProxy: null == systemProxy ? _self.systemProxy : systemProxy // ignore: cast_nullable_to_non_nullable
as bool,bypassDomain: null == bypassDomain ? _self._bypassDomain : bypassDomain // ignore: cast_nullable_to_non_nullable
as List<String>,stack: null == stack ? _self.stack : stack // ignore: cast_nullable_to_non_nullable
as String,routeAddress: null == routeAddress ? _self._routeAddress : routeAddress // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of VpnOptions
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccessControlPropsCopyWith<$Res> get accessControlProps {

  return $AccessControlPropsCopyWith<$Res>(_self.accessControlProps, (value) {
    return _then(_self.copyWith(accessControlProps: value));
  });
}
}


/// @nodoc
mixin _$InitParams {

@JsonKey(name: 'home-dir') String get homeDir; int get version;
/// Create a copy of InitParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitParamsCopyWith<InitParams> get copyWith => _$InitParamsCopyWithImpl<InitParams>(this as InitParams, _$identity);

  /// Serializes this InitParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitParams&&(identical(other.homeDir, homeDir) || other.homeDir == homeDir)&&(identical(other.version, version) || other.version == version));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,homeDir,version);

@override
String toString() {
  return 'InitParams(homeDir: $homeDir, version: $version)';
}


}

/// @nodoc
abstract mixin class $InitParamsCopyWith<$Res>  {
  factory $InitParamsCopyWith(InitParams value, $Res Function(InitParams) _then) = _$InitParamsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'home-dir') String homeDir, int version
});




}
/// @nodoc
class _$InitParamsCopyWithImpl<$Res>
    implements $InitParamsCopyWith<$Res> {
  _$InitParamsCopyWithImpl(this._self, this._then);

  final InitParams _self;
  final $Res Function(InitParams) _then;

/// Create a copy of InitParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? homeDir = null,Object? version = null,}) {
  return _then(_self.copyWith(
homeDir: null == homeDir ? _self.homeDir : homeDir // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [InitParams].
extension InitParamsPatterns on InitParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InitParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InitParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InitParams value)  $default,){
final _that = this;
switch (_that) {
case _InitParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InitParams value)?  $default,){
final _that = this;
switch (_that) {
case _InitParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'home-dir')  String homeDir,  int version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InitParams() when $default != null:
return $default(_that.homeDir,_that.version);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'home-dir')  String homeDir,  int version)  $default,) {final _that = this;
switch (_that) {
case _InitParams():
return $default(_that.homeDir,_that.version);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'home-dir')  String homeDir,  int version)?  $default,) {final _that = this;
switch (_that) {
case _InitParams() when $default != null:
return $default(_that.homeDir,_that.version);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InitParams implements InitParams {
  const _InitParams({@JsonKey(name: 'home-dir') required this.homeDir, required this.version});
  factory _InitParams.fromJson(Map<String, dynamic> json) => _$InitParamsFromJson(json);

@override@JsonKey(name: 'home-dir') final  String homeDir;
@override final  int version;

/// Create a copy of InitParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InitParamsCopyWith<_InitParams> get copyWith => __$InitParamsCopyWithImpl<_InitParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InitParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InitParams&&(identical(other.homeDir, homeDir) || other.homeDir == homeDir)&&(identical(other.version, version) || other.version == version));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,homeDir,version);

@override
String toString() {
  return 'InitParams(homeDir: $homeDir, version: $version)';
}


}

/// @nodoc
abstract mixin class _$InitParamsCopyWith<$Res> implements $InitParamsCopyWith<$Res> {
  factory _$InitParamsCopyWith(_InitParams value, $Res Function(_InitParams) _then) = __$InitParamsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'home-dir') String homeDir, int version
});




}
/// @nodoc
class __$InitParamsCopyWithImpl<$Res>
    implements _$InitParamsCopyWith<$Res> {
  __$InitParamsCopyWithImpl(this._self, this._then);

  final _InitParams _self;
  final $Res Function(_InitParams) _then;

/// Create a copy of InitParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? homeDir = null,Object? version = null,}) {
  return _then(_InitParams(
homeDir: null == homeDir ? _self.homeDir : homeDir // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ChangeProxyParams {

@JsonKey(name: 'group-name') String? get groupName;@JsonKey(name: 'proxy-name') String? get proxyName;@JsonKey(name: 'group-id') String? get groupId;@JsonKey(name: 'member-id') String? get memberId; int? get generation;
/// Create a copy of ChangeProxyParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeProxyParamsCopyWith<ChangeProxyParams> get copyWith => _$ChangeProxyParamsCopyWithImpl<ChangeProxyParams>(this as ChangeProxyParams, _$identity);

  /// Serializes this ChangeProxyParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeProxyParams&&(identical(other.groupName, groupName) || other.groupName == groupName)&&(identical(other.proxyName, proxyName) || other.proxyName == proxyName)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.generation, generation) || other.generation == generation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,groupName,proxyName,groupId,memberId,generation);

@override
String toString() {
  return 'ChangeProxyParams(groupName: $groupName, proxyName: $proxyName, groupId: $groupId, memberId: $memberId, generation: $generation)';
}


}

/// @nodoc
abstract mixin class $ChangeProxyParamsCopyWith<$Res>  {
  factory $ChangeProxyParamsCopyWith(ChangeProxyParams value, $Res Function(ChangeProxyParams) _then) = _$ChangeProxyParamsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'group-name') String? groupName,@JsonKey(name: 'proxy-name') String? proxyName,@JsonKey(name: 'group-id') String? groupId,@JsonKey(name: 'member-id') String? memberId, int? generation
});




}
/// @nodoc
class _$ChangeProxyParamsCopyWithImpl<$Res>
    implements $ChangeProxyParamsCopyWith<$Res> {
  _$ChangeProxyParamsCopyWithImpl(this._self, this._then);

  final ChangeProxyParams _self;
  final $Res Function(ChangeProxyParams) _then;

/// Create a copy of ChangeProxyParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? groupName = freezed,Object? proxyName = freezed,Object? groupId = freezed,Object? memberId = freezed,Object? generation = freezed,}) {
  return _then(_self.copyWith(
groupName: freezed == groupName ? _self.groupName : groupName // ignore: cast_nullable_to_non_nullable
as String?,proxyName: freezed == proxyName ? _self.proxyName : proxyName // ignore: cast_nullable_to_non_nullable
as String?,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String?,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,generation: freezed == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChangeProxyParams].
extension ChangeProxyParamsPatterns on ChangeProxyParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChangeProxyParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChangeProxyParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChangeProxyParams value)  $default,){
final _that = this;
switch (_that) {
case _ChangeProxyParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChangeProxyParams value)?  $default,){
final _that = this;
switch (_that) {
case _ChangeProxyParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'group-name')  String? groupName, @JsonKey(name: 'proxy-name')  String? proxyName, @JsonKey(name: 'group-id')  String? groupId, @JsonKey(name: 'member-id')  String? memberId,  int? generation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChangeProxyParams() when $default != null:
return $default(_that.groupName,_that.proxyName,_that.groupId,_that.memberId,_that.generation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'group-name')  String? groupName, @JsonKey(name: 'proxy-name')  String? proxyName, @JsonKey(name: 'group-id')  String? groupId, @JsonKey(name: 'member-id')  String? memberId,  int? generation)  $default,) {final _that = this;
switch (_that) {
case _ChangeProxyParams():
return $default(_that.groupName,_that.proxyName,_that.groupId,_that.memberId,_that.generation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'group-name')  String? groupName, @JsonKey(name: 'proxy-name')  String? proxyName, @JsonKey(name: 'group-id')  String? groupId, @JsonKey(name: 'member-id')  String? memberId,  int? generation)?  $default,) {final _that = this;
switch (_that) {
case _ChangeProxyParams() when $default != null:
return $default(_that.groupName,_that.proxyName,_that.groupId,_that.memberId,_that.generation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChangeProxyParams implements ChangeProxyParams {
  const _ChangeProxyParams({@JsonKey(name: 'group-name') this.groupName, @JsonKey(name: 'proxy-name') this.proxyName, @JsonKey(name: 'group-id') this.groupId, @JsonKey(name: 'member-id') this.memberId, this.generation});
  factory _ChangeProxyParams.fromJson(Map<String, dynamic> json) => _$ChangeProxyParamsFromJson(json);

@override@JsonKey(name: 'group-name') final  String? groupName;
@override@JsonKey(name: 'proxy-name') final  String? proxyName;
@override@JsonKey(name: 'group-id') final  String? groupId;
@override@JsonKey(name: 'member-id') final  String? memberId;
@override final  int? generation;

/// Create a copy of ChangeProxyParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChangeProxyParamsCopyWith<_ChangeProxyParams> get copyWith => __$ChangeProxyParamsCopyWithImpl<_ChangeProxyParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChangeProxyParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChangeProxyParams&&(identical(other.groupName, groupName) || other.groupName == groupName)&&(identical(other.proxyName, proxyName) || other.proxyName == proxyName)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.generation, generation) || other.generation == generation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,groupName,proxyName,groupId,memberId,generation);

@override
String toString() {
  return 'ChangeProxyParams(groupName: $groupName, proxyName: $proxyName, groupId: $groupId, memberId: $memberId, generation: $generation)';
}


}

/// @nodoc
abstract mixin class _$ChangeProxyParamsCopyWith<$Res> implements $ChangeProxyParamsCopyWith<$Res> {
  factory _$ChangeProxyParamsCopyWith(_ChangeProxyParams value, $Res Function(_ChangeProxyParams) _then) = __$ChangeProxyParamsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'group-name') String? groupName,@JsonKey(name: 'proxy-name') String? proxyName,@JsonKey(name: 'group-id') String? groupId,@JsonKey(name: 'member-id') String? memberId, int? generation
});




}
/// @nodoc
class __$ChangeProxyParamsCopyWithImpl<$Res>
    implements _$ChangeProxyParamsCopyWith<$Res> {
  __$ChangeProxyParamsCopyWithImpl(this._self, this._then);

  final _ChangeProxyParams _self;
  final $Res Function(_ChangeProxyParams) _then;

/// Create a copy of ChangeProxyParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? groupName = freezed,Object? proxyName = freezed,Object? groupId = freezed,Object? memberId = freezed,Object? generation = freezed,}) {
  return _then(_ChangeProxyParams(
groupName: freezed == groupName ? _self.groupName : groupName // ignore: cast_nullable_to_non_nullable
as String?,proxyName: freezed == proxyName ? _self.proxyName : proxyName // ignore: cast_nullable_to_non_nullable
as String?,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String?,memberId: freezed == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String?,generation: freezed == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$UpdateGeoDataParams {

@JsonKey(name: 'geo-type') String get geoType;@JsonKey(name: 'geo-name') String get geoName;
/// Create a copy of UpdateGeoDataParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateGeoDataParamsCopyWith<UpdateGeoDataParams> get copyWith => _$UpdateGeoDataParamsCopyWithImpl<UpdateGeoDataParams>(this as UpdateGeoDataParams, _$identity);

  /// Serializes this UpdateGeoDataParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateGeoDataParams&&(identical(other.geoType, geoType) || other.geoType == geoType)&&(identical(other.geoName, geoName) || other.geoName == geoName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,geoType,geoName);

@override
String toString() {
  return 'UpdateGeoDataParams(geoType: $geoType, geoName: $geoName)';
}


}

/// @nodoc
abstract mixin class $UpdateGeoDataParamsCopyWith<$Res>  {
  factory $UpdateGeoDataParamsCopyWith(UpdateGeoDataParams value, $Res Function(UpdateGeoDataParams) _then) = _$UpdateGeoDataParamsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'geo-type') String geoType,@JsonKey(name: 'geo-name') String geoName
});




}
/// @nodoc
class _$UpdateGeoDataParamsCopyWithImpl<$Res>
    implements $UpdateGeoDataParamsCopyWith<$Res> {
  _$UpdateGeoDataParamsCopyWithImpl(this._self, this._then);

  final UpdateGeoDataParams _self;
  final $Res Function(UpdateGeoDataParams) _then;

/// Create a copy of UpdateGeoDataParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? geoType = null,Object? geoName = null,}) {
  return _then(_self.copyWith(
geoType: null == geoType ? _self.geoType : geoType // ignore: cast_nullable_to_non_nullable
as String,geoName: null == geoName ? _self.geoName : geoName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateGeoDataParams].
extension UpdateGeoDataParamsPatterns on UpdateGeoDataParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateGeoDataParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateGeoDataParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateGeoDataParams value)  $default,){
final _that = this;
switch (_that) {
case _UpdateGeoDataParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateGeoDataParams value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateGeoDataParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'geo-type')  String geoType, @JsonKey(name: 'geo-name')  String geoName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateGeoDataParams() when $default != null:
return $default(_that.geoType,_that.geoName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'geo-type')  String geoType, @JsonKey(name: 'geo-name')  String geoName)  $default,) {final _that = this;
switch (_that) {
case _UpdateGeoDataParams():
return $default(_that.geoType,_that.geoName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'geo-type')  String geoType, @JsonKey(name: 'geo-name')  String geoName)?  $default,) {final _that = this;
switch (_that) {
case _UpdateGeoDataParams() when $default != null:
return $default(_that.geoType,_that.geoName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UpdateGeoDataParams implements UpdateGeoDataParams {
  const _UpdateGeoDataParams({@JsonKey(name: 'geo-type') required this.geoType, @JsonKey(name: 'geo-name') required this.geoName});
  factory _UpdateGeoDataParams.fromJson(Map<String, dynamic> json) => _$UpdateGeoDataParamsFromJson(json);

@override@JsonKey(name: 'geo-type') final  String geoType;
@override@JsonKey(name: 'geo-name') final  String geoName;

/// Create a copy of UpdateGeoDataParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateGeoDataParamsCopyWith<_UpdateGeoDataParams> get copyWith => __$UpdateGeoDataParamsCopyWithImpl<_UpdateGeoDataParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UpdateGeoDataParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateGeoDataParams&&(identical(other.geoType, geoType) || other.geoType == geoType)&&(identical(other.geoName, geoName) || other.geoName == geoName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,geoType,geoName);

@override
String toString() {
  return 'UpdateGeoDataParams(geoType: $geoType, geoName: $geoName)';
}


}

/// @nodoc
abstract mixin class _$UpdateGeoDataParamsCopyWith<$Res> implements $UpdateGeoDataParamsCopyWith<$Res> {
  factory _$UpdateGeoDataParamsCopyWith(_UpdateGeoDataParams value, $Res Function(_UpdateGeoDataParams) _then) = __$UpdateGeoDataParamsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'geo-type') String geoType,@JsonKey(name: 'geo-name') String geoName
});




}
/// @nodoc
class __$UpdateGeoDataParamsCopyWithImpl<$Res>
    implements _$UpdateGeoDataParamsCopyWith<$Res> {
  __$UpdateGeoDataParamsCopyWithImpl(this._self, this._then);

  final _UpdateGeoDataParams _self;
  final $Res Function(_UpdateGeoDataParams) _then;

/// Create a copy of UpdateGeoDataParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? geoType = null,Object? geoName = null,}) {
  return _then(_UpdateGeoDataParams(
geoType: null == geoType ? _self.geoType : geoType // ignore: cast_nullable_to_non_nullable
as String,geoName: null == geoName ? _self.geoName : geoName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$CoreEvent {

 CoreEventType get type; dynamic get data;
/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEventCopyWith<CoreEvent> get copyWith => _$CoreEventCopyWithImpl<CoreEvent>(this as CoreEvent, _$identity);

  /// Serializes this CoreEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.data, data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'CoreEvent(type: $type, data: $data)';
}


}

/// @nodoc
abstract mixin class $CoreEventCopyWith<$Res>  {
  factory $CoreEventCopyWith(CoreEvent value, $Res Function(CoreEvent) _then) = _$CoreEventCopyWithImpl;
@useResult
$Res call({
 CoreEventType type, dynamic data
});




}
/// @nodoc
class _$CoreEventCopyWithImpl<$Res>
    implements $CoreEventCopyWith<$Res> {
  _$CoreEventCopyWithImpl(this._self, this._then);

  final CoreEvent _self;
  final $Res Function(CoreEvent) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? data = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as CoreEventType,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}

}


/// Adds pattern-matching-related methods to [CoreEvent].
extension CoreEventPatterns on CoreEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoreEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoreEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoreEvent value)  $default,){
final _that = this;
switch (_that) {
case _CoreEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoreEvent value)?  $default,){
final _that = this;
switch (_that) {
case _CoreEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CoreEventType type,  dynamic data)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoreEvent() when $default != null:
return $default(_that.type,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CoreEventType type,  dynamic data)  $default,) {final _that = this;
switch (_that) {
case _CoreEvent():
return $default(_that.type,_that.data);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CoreEventType type,  dynamic data)?  $default,) {final _that = this;
switch (_that) {
case _CoreEvent() when $default != null:
return $default(_that.type,_that.data);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CoreEvent implements CoreEvent {
  const _CoreEvent({required this.type, this.data});
  factory _CoreEvent.fromJson(Map<String, dynamic> json) => _$CoreEventFromJson(json);

@override final  CoreEventType type;
@override final  dynamic data;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoreEventCopyWith<_CoreEvent> get copyWith => __$CoreEventCopyWithImpl<_CoreEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CoreEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoreEvent&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.data, data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'CoreEvent(type: $type, data: $data)';
}


}

/// @nodoc
abstract mixin class _$CoreEventCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory _$CoreEventCopyWith(_CoreEvent value, $Res Function(_CoreEvent) _then) = __$CoreEventCopyWithImpl;
@override @useResult
$Res call({
 CoreEventType type, dynamic data
});




}
/// @nodoc
class __$CoreEventCopyWithImpl<$Res>
    implements _$CoreEventCopyWith<$Res> {
  __$CoreEventCopyWithImpl(this._self, this._then);

  final _CoreEvent _self;
  final $Res Function(_CoreEvent) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? data = freezed,}) {
  return _then(_CoreEvent(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as CoreEventType,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}


}


/// @nodoc
mixin _$InvokeMessage {

 InvokeMessageType get type; dynamic get data;
/// Create a copy of InvokeMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InvokeMessageCopyWith<InvokeMessage> get copyWith => _$InvokeMessageCopyWithImpl<InvokeMessage>(this as InvokeMessage, _$identity);

  /// Serializes this InvokeMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InvokeMessage&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.data, data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'InvokeMessage(type: $type, data: $data)';
}


}

/// @nodoc
abstract mixin class $InvokeMessageCopyWith<$Res>  {
  factory $InvokeMessageCopyWith(InvokeMessage value, $Res Function(InvokeMessage) _then) = _$InvokeMessageCopyWithImpl;
@useResult
$Res call({
 InvokeMessageType type, dynamic data
});




}
/// @nodoc
class _$InvokeMessageCopyWithImpl<$Res>
    implements $InvokeMessageCopyWith<$Res> {
  _$InvokeMessageCopyWithImpl(this._self, this._then);

  final InvokeMessage _self;
  final $Res Function(InvokeMessage) _then;

/// Create a copy of InvokeMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? data = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as InvokeMessageType,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}

}


/// Adds pattern-matching-related methods to [InvokeMessage].
extension InvokeMessagePatterns on InvokeMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InvokeMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InvokeMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InvokeMessage value)  $default,){
final _that = this;
switch (_that) {
case _InvokeMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InvokeMessage value)?  $default,){
final _that = this;
switch (_that) {
case _InvokeMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InvokeMessageType type,  dynamic data)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InvokeMessage() when $default != null:
return $default(_that.type,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InvokeMessageType type,  dynamic data)  $default,) {final _that = this;
switch (_that) {
case _InvokeMessage():
return $default(_that.type,_that.data);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InvokeMessageType type,  dynamic data)?  $default,) {final _that = this;
switch (_that) {
case _InvokeMessage() when $default != null:
return $default(_that.type,_that.data);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InvokeMessage implements InvokeMessage {
  const _InvokeMessage({required this.type, this.data});
  factory _InvokeMessage.fromJson(Map<String, dynamic> json) => _$InvokeMessageFromJson(json);

@override final  InvokeMessageType type;
@override final  dynamic data;

/// Create a copy of InvokeMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InvokeMessageCopyWith<_InvokeMessage> get copyWith => __$InvokeMessageCopyWithImpl<_InvokeMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InvokeMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InvokeMessage&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.data, data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'InvokeMessage(type: $type, data: $data)';
}


}

/// @nodoc
abstract mixin class _$InvokeMessageCopyWith<$Res> implements $InvokeMessageCopyWith<$Res> {
  factory _$InvokeMessageCopyWith(_InvokeMessage value, $Res Function(_InvokeMessage) _then) = __$InvokeMessageCopyWithImpl;
@override @useResult
$Res call({
 InvokeMessageType type, dynamic data
});




}
/// @nodoc
class __$InvokeMessageCopyWithImpl<$Res>
    implements _$InvokeMessageCopyWith<$Res> {
  __$InvokeMessageCopyWithImpl(this._self, this._then);

  final _InvokeMessage _self;
  final $Res Function(_InvokeMessage) _then;

/// Create a copy of InvokeMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? data = freezed,}) {
  return _then(_InvokeMessage(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as InvokeMessageType,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}


}


/// @nodoc
mixin _$Delay {

 String get name; String get url; int? get value;
/// Create a copy of Delay
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DelayCopyWith<Delay> get copyWith => _$DelayCopyWithImpl<Delay>(this as Delay, _$identity);

  /// Serializes this Delay to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Delay&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,url,value);

@override
String toString() {
  return 'Delay(name: $name, url: $url, value: $value)';
}


}

/// @nodoc
abstract mixin class $DelayCopyWith<$Res>  {
  factory $DelayCopyWith(Delay value, $Res Function(Delay) _then) = _$DelayCopyWithImpl;
@useResult
$Res call({
 String name, String url, int? value
});




}
/// @nodoc
class _$DelayCopyWithImpl<$Res>
    implements $DelayCopyWith<$Res> {
  _$DelayCopyWithImpl(this._self, this._then);

  final Delay _self;
  final $Res Function(Delay) _then;

/// Create a copy of Delay
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? url = null,Object? value = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Delay].
extension DelayPatterns on Delay {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Delay value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Delay() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Delay value)  $default,){
final _that = this;
switch (_that) {
case _Delay():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Delay value)?  $default,){
final _that = this;
switch (_that) {
case _Delay() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String url,  int? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Delay() when $default != null:
return $default(_that.name,_that.url,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String url,  int? value)  $default,) {final _that = this;
switch (_that) {
case _Delay():
return $default(_that.name,_that.url,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String url,  int? value)?  $default,) {final _that = this;
switch (_that) {
case _Delay() when $default != null:
return $default(_that.name,_that.url,_that.value);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Delay implements Delay {
  const _Delay({required this.name, required this.url, this.value});
  factory _Delay.fromJson(Map<String, dynamic> json) => _$DelayFromJson(json);

@override final  String name;
@override final  String url;
@override final  int? value;

/// Create a copy of Delay
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DelayCopyWith<_Delay> get copyWith => __$DelayCopyWithImpl<_Delay>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DelayToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Delay&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,url,value);

@override
String toString() {
  return 'Delay(name: $name, url: $url, value: $value)';
}


}

/// @nodoc
abstract mixin class _$DelayCopyWith<$Res> implements $DelayCopyWith<$Res> {
  factory _$DelayCopyWith(_Delay value, $Res Function(_Delay) _then) = __$DelayCopyWithImpl;
@override @useResult
$Res call({
 String name, String url, int? value
});




}
/// @nodoc
class __$DelayCopyWithImpl<$Res>
    implements _$DelayCopyWith<$Res> {
  __$DelayCopyWithImpl(this._self, this._then);

  final _Delay _self;
  final $Res Function(_Delay) _then;

/// Create a copy of Delay
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? url = null,Object? value = freezed,}) {
  return _then(_Delay(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$Now {

 String get name; String get value;
/// Create a copy of Now
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NowCopyWith<Now> get copyWith => _$NowCopyWithImpl<Now>(this as Now, _$identity);

  /// Serializes this Now to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Now&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,value);

@override
String toString() {
  return 'Now(name: $name, value: $value)';
}


}

/// @nodoc
abstract mixin class $NowCopyWith<$Res>  {
  factory $NowCopyWith(Now value, $Res Function(Now) _then) = _$NowCopyWithImpl;
@useResult
$Res call({
 String name, String value
});




}
/// @nodoc
class _$NowCopyWithImpl<$Res>
    implements $NowCopyWith<$Res> {
  _$NowCopyWithImpl(this._self, this._then);

  final Now _self;
  final $Res Function(Now) _then;

/// Create a copy of Now
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? value = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Now].
extension NowPatterns on Now {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Now value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Now() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Now value)  $default,){
final _that = this;
switch (_that) {
case _Now():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Now value)?  $default,){
final _that = this;
switch (_that) {
case _Now() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Now() when $default != null:
return $default(_that.name,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String value)  $default,) {final _that = this;
switch (_that) {
case _Now():
return $default(_that.name,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String value)?  $default,) {final _that = this;
switch (_that) {
case _Now() when $default != null:
return $default(_that.name,_that.value);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Now implements Now {
  const _Now({required this.name, required this.value});
  factory _Now.fromJson(Map<String, dynamic> json) => _$NowFromJson(json);

@override final  String name;
@override final  String value;

/// Create a copy of Now
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NowCopyWith<_Now> get copyWith => __$NowCopyWithImpl<_Now>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NowToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Now&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,value);

@override
String toString() {
  return 'Now(name: $name, value: $value)';
}


}

/// @nodoc
abstract mixin class _$NowCopyWith<$Res> implements $NowCopyWith<$Res> {
  factory _$NowCopyWith(_Now value, $Res Function(_Now) _then) = __$NowCopyWithImpl;
@override @useResult
$Res call({
 String name, String value
});




}
/// @nodoc
class __$NowCopyWithImpl<$Res>
    implements _$NowCopyWith<$Res> {
  __$NowCopyWithImpl(this._self, this._then);

  final _Now _self;
  final $Res Function(_Now) _then;

/// Create a copy of Now
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? value = null,}) {
  return _then(_Now(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ProviderSubscriptionInfo {

@JsonKey(name: 'UPLOAD') int get upload;@JsonKey(name: 'DOWNLOAD') int get download;@JsonKey(name: 'TOTAL') int get total;@JsonKey(name: 'EXPIRE') int get expire;
/// Create a copy of ProviderSubscriptionInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProviderSubscriptionInfoCopyWith<ProviderSubscriptionInfo> get copyWith => _$ProviderSubscriptionInfoCopyWithImpl<ProviderSubscriptionInfo>(this as ProviderSubscriptionInfo, _$identity);

  /// Serializes this ProviderSubscriptionInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProviderSubscriptionInfo&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.download, download) || other.download == download)&&(identical(other.total, total) || other.total == total)&&(identical(other.expire, expire) || other.expire == expire));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,upload,download,total,expire);

@override
String toString() {
  return 'ProviderSubscriptionInfo(upload: $upload, download: $download, total: $total, expire: $expire)';
}


}

/// @nodoc
abstract mixin class $ProviderSubscriptionInfoCopyWith<$Res>  {
  factory $ProviderSubscriptionInfoCopyWith(ProviderSubscriptionInfo value, $Res Function(ProviderSubscriptionInfo) _then) = _$ProviderSubscriptionInfoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'UPLOAD') int upload,@JsonKey(name: 'DOWNLOAD') int download,@JsonKey(name: 'TOTAL') int total,@JsonKey(name: 'EXPIRE') int expire
});




}
/// @nodoc
class _$ProviderSubscriptionInfoCopyWithImpl<$Res>
    implements $ProviderSubscriptionInfoCopyWith<$Res> {
  _$ProviderSubscriptionInfoCopyWithImpl(this._self, this._then);

  final ProviderSubscriptionInfo _self;
  final $Res Function(ProviderSubscriptionInfo) _then;

/// Create a copy of ProviderSubscriptionInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? upload = null,Object? download = null,Object? total = null,Object? expire = null,}) {
  return _then(_self.copyWith(
upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as int,download: null == download ? _self.download : download // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,expire: null == expire ? _self.expire : expire // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProviderSubscriptionInfo].
extension ProviderSubscriptionInfoPatterns on ProviderSubscriptionInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProviderSubscriptionInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProviderSubscriptionInfo value)  $default,){
final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProviderSubscriptionInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'UPLOAD')  int upload, @JsonKey(name: 'DOWNLOAD')  int download, @JsonKey(name: 'TOTAL')  int total, @JsonKey(name: 'EXPIRE')  int expire)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo() when $default != null:
return $default(_that.upload,_that.download,_that.total,_that.expire);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'UPLOAD')  int upload, @JsonKey(name: 'DOWNLOAD')  int download, @JsonKey(name: 'TOTAL')  int total, @JsonKey(name: 'EXPIRE')  int expire)  $default,) {final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo():
return $default(_that.upload,_that.download,_that.total,_that.expire);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'UPLOAD')  int upload, @JsonKey(name: 'DOWNLOAD')  int download, @JsonKey(name: 'TOTAL')  int total, @JsonKey(name: 'EXPIRE')  int expire)?  $default,) {final _that = this;
switch (_that) {
case _ProviderSubscriptionInfo() when $default != null:
return $default(_that.upload,_that.download,_that.total,_that.expire);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProviderSubscriptionInfo implements ProviderSubscriptionInfo {
  const _ProviderSubscriptionInfo({@JsonKey(name: 'UPLOAD') this.upload = 0, @JsonKey(name: 'DOWNLOAD') this.download = 0, @JsonKey(name: 'TOTAL') this.total = 0, @JsonKey(name: 'EXPIRE') this.expire = 0});
  factory _ProviderSubscriptionInfo.fromJson(Map<String, dynamic> json) => _$ProviderSubscriptionInfoFromJson(json);

@override@JsonKey(name: 'UPLOAD') final  int upload;
@override@JsonKey(name: 'DOWNLOAD') final  int download;
@override@JsonKey(name: 'TOTAL') final  int total;
@override@JsonKey(name: 'EXPIRE') final  int expire;

/// Create a copy of ProviderSubscriptionInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProviderSubscriptionInfoCopyWith<_ProviderSubscriptionInfo> get copyWith => __$ProviderSubscriptionInfoCopyWithImpl<_ProviderSubscriptionInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProviderSubscriptionInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProviderSubscriptionInfo&&(identical(other.upload, upload) || other.upload == upload)&&(identical(other.download, download) || other.download == download)&&(identical(other.total, total) || other.total == total)&&(identical(other.expire, expire) || other.expire == expire));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,upload,download,total,expire);

@override
String toString() {
  return 'ProviderSubscriptionInfo(upload: $upload, download: $download, total: $total, expire: $expire)';
}


}

/// @nodoc
abstract mixin class _$ProviderSubscriptionInfoCopyWith<$Res> implements $ProviderSubscriptionInfoCopyWith<$Res> {
  factory _$ProviderSubscriptionInfoCopyWith(_ProviderSubscriptionInfo value, $Res Function(_ProviderSubscriptionInfo) _then) = __$ProviderSubscriptionInfoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'UPLOAD') int upload,@JsonKey(name: 'DOWNLOAD') int download,@JsonKey(name: 'TOTAL') int total,@JsonKey(name: 'EXPIRE') int expire
});




}
/// @nodoc
class __$ProviderSubscriptionInfoCopyWithImpl<$Res>
    implements _$ProviderSubscriptionInfoCopyWith<$Res> {
  __$ProviderSubscriptionInfoCopyWithImpl(this._self, this._then);

  final _ProviderSubscriptionInfo _self;
  final $Res Function(_ProviderSubscriptionInfo) _then;

/// Create a copy of ProviderSubscriptionInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? upload = null,Object? download = null,Object? total = null,Object? expire = null,}) {
  return _then(_ProviderSubscriptionInfo(
upload: null == upload ? _self.upload : upload // ignore: cast_nullable_to_non_nullable
as int,download: null == download ? _self.download : download // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,expire: null == expire ? _self.expire : expire // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ExternalProvider {

 String get name; String get type; String? get path; int get count;@JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore) SubscriptionInfo? get subscriptionInfo;@JsonKey(name: 'vehicle-type') String get vehicleType;@JsonKey(name: 'update-at') DateTime get updateAt;
/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExternalProviderCopyWith<ExternalProvider> get copyWith => _$ExternalProviderCopyWithImpl<ExternalProvider>(this as ExternalProvider, _$identity);

  /// Serializes this ExternalProvider to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExternalProvider&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.path, path) || other.path == path)&&(identical(other.count, count) || other.count == count)&&(identical(other.subscriptionInfo, subscriptionInfo) || other.subscriptionInfo == subscriptionInfo)&&(identical(other.vehicleType, vehicleType) || other.vehicleType == vehicleType)&&(identical(other.updateAt, updateAt) || other.updateAt == updateAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,type,path,count,subscriptionInfo,vehicleType,updateAt);

@override
String toString() {
  return 'ExternalProvider(name: $name, type: $type, path: $path, count: $count, subscriptionInfo: $subscriptionInfo, vehicleType: $vehicleType, updateAt: $updateAt)';
}


}

/// @nodoc
abstract mixin class $ExternalProviderCopyWith<$Res>  {
  factory $ExternalProviderCopyWith(ExternalProvider value, $Res Function(ExternalProvider) _then) = _$ExternalProviderCopyWithImpl;
@useResult
$Res call({
 String name, String type, String? path, int count,@JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore) SubscriptionInfo? subscriptionInfo,@JsonKey(name: 'vehicle-type') String vehicleType,@JsonKey(name: 'update-at') DateTime updateAt
});


$SubscriptionInfoCopyWith<$Res>? get subscriptionInfo;

}
/// @nodoc
class _$ExternalProviderCopyWithImpl<$Res>
    implements $ExternalProviderCopyWith<$Res> {
  _$ExternalProviderCopyWithImpl(this._self, this._then);

  final ExternalProvider _self;
  final $Res Function(ExternalProvider) _then;

/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? type = null,Object? path = freezed,Object? count = null,Object? subscriptionInfo = freezed,Object? vehicleType = null,Object? updateAt = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,subscriptionInfo: freezed == subscriptionInfo ? _self.subscriptionInfo : subscriptionInfo // ignore: cast_nullable_to_non_nullable
as SubscriptionInfo?,vehicleType: null == vehicleType ? _self.vehicleType : vehicleType // ignore: cast_nullable_to_non_nullable
as String,updateAt: null == updateAt ? _self.updateAt : updateAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}
/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubscriptionInfoCopyWith<$Res>? get subscriptionInfo {
    if (_self.subscriptionInfo == null) {
    return null;
  }

  return $SubscriptionInfoCopyWith<$Res>(_self.subscriptionInfo!, (value) {
    return _then(_self.copyWith(subscriptionInfo: value));
  });
}
}


/// Adds pattern-matching-related methods to [ExternalProvider].
extension ExternalProviderPatterns on ExternalProvider {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExternalProvider value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExternalProvider() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExternalProvider value)  $default,){
final _that = this;
switch (_that) {
case _ExternalProvider():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExternalProvider value)?  $default,){
final _that = this;
switch (_that) {
case _ExternalProvider() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String type,  String? path,  int count, @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)  SubscriptionInfo? subscriptionInfo, @JsonKey(name: 'vehicle-type')  String vehicleType, @JsonKey(name: 'update-at')  DateTime updateAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExternalProvider() when $default != null:
return $default(_that.name,_that.type,_that.path,_that.count,_that.subscriptionInfo,_that.vehicleType,_that.updateAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String type,  String? path,  int count, @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)  SubscriptionInfo? subscriptionInfo, @JsonKey(name: 'vehicle-type')  String vehicleType, @JsonKey(name: 'update-at')  DateTime updateAt)  $default,) {final _that = this;
switch (_that) {
case _ExternalProvider():
return $default(_that.name,_that.type,_that.path,_that.count,_that.subscriptionInfo,_that.vehicleType,_that.updateAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String type,  String? path,  int count, @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)  SubscriptionInfo? subscriptionInfo, @JsonKey(name: 'vehicle-type')  String vehicleType, @JsonKey(name: 'update-at')  DateTime updateAt)?  $default,) {final _that = this;
switch (_that) {
case _ExternalProvider() when $default != null:
return $default(_that.name,_that.type,_that.path,_that.count,_that.subscriptionInfo,_that.vehicleType,_that.updateAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExternalProvider implements ExternalProvider {
  const _ExternalProvider({required this.name, required this.type, this.path, required this.count, @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore) this.subscriptionInfo, @JsonKey(name: 'vehicle-type') required this.vehicleType, @JsonKey(name: 'update-at') required this.updateAt});
  factory _ExternalProvider.fromJson(Map<String, dynamic> json) => _$ExternalProviderFromJson(json);

@override final  String name;
@override final  String type;
@override final  String? path;
@override final  int count;
@override@JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore) final  SubscriptionInfo? subscriptionInfo;
@override@JsonKey(name: 'vehicle-type') final  String vehicleType;
@override@JsonKey(name: 'update-at') final  DateTime updateAt;

/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExternalProviderCopyWith<_ExternalProvider> get copyWith => __$ExternalProviderCopyWithImpl<_ExternalProvider>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExternalProviderToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExternalProvider&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.path, path) || other.path == path)&&(identical(other.count, count) || other.count == count)&&(identical(other.subscriptionInfo, subscriptionInfo) || other.subscriptionInfo == subscriptionInfo)&&(identical(other.vehicleType, vehicleType) || other.vehicleType == vehicleType)&&(identical(other.updateAt, updateAt) || other.updateAt == updateAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,type,path,count,subscriptionInfo,vehicleType,updateAt);

@override
String toString() {
  return 'ExternalProvider(name: $name, type: $type, path: $path, count: $count, subscriptionInfo: $subscriptionInfo, vehicleType: $vehicleType, updateAt: $updateAt)';
}


}

/// @nodoc
abstract mixin class _$ExternalProviderCopyWith<$Res> implements $ExternalProviderCopyWith<$Res> {
  factory _$ExternalProviderCopyWith(_ExternalProvider value, $Res Function(_ExternalProvider) _then) = __$ExternalProviderCopyWithImpl;
@override @useResult
$Res call({
 String name, String type, String? path, int count,@JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore) SubscriptionInfo? subscriptionInfo,@JsonKey(name: 'vehicle-type') String vehicleType,@JsonKey(name: 'update-at') DateTime updateAt
});


@override $SubscriptionInfoCopyWith<$Res>? get subscriptionInfo;

}
/// @nodoc
class __$ExternalProviderCopyWithImpl<$Res>
    implements _$ExternalProviderCopyWith<$Res> {
  __$ExternalProviderCopyWithImpl(this._self, this._then);

  final _ExternalProvider _self;
  final $Res Function(_ExternalProvider) _then;

/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? type = null,Object? path = freezed,Object? count = null,Object? subscriptionInfo = freezed,Object? vehicleType = null,Object? updateAt = null,}) {
  return _then(_ExternalProvider(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,subscriptionInfo: freezed == subscriptionInfo ? _self.subscriptionInfo : subscriptionInfo // ignore: cast_nullable_to_non_nullable
as SubscriptionInfo?,vehicleType: null == vehicleType ? _self.vehicleType : vehicleType // ignore: cast_nullable_to_non_nullable
as String,updateAt: null == updateAt ? _self.updateAt : updateAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

/// Create a copy of ExternalProvider
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubscriptionInfoCopyWith<$Res>? get subscriptionInfo {
    if (_self.subscriptionInfo == null) {
    return null;
  }

  return $SubscriptionInfoCopyWith<$Res>(_self.subscriptionInfo!, (value) {
    return _then(_self.copyWith(subscriptionInfo: value));
  });
}
}


/// @nodoc
mixin _$Action {

 ActionMethod get method; dynamic get data; String get id;
/// Create a copy of Action
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionCopyWith<Action> get copyWith => _$ActionCopyWithImpl<Action>(this as Action, _$identity);

  /// Serializes this Action to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Action&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,method,const DeepCollectionEquality().hash(data),id);

@override
String toString() {
  return 'Action(method: $method, data: $data, id: $id)';
}


}

/// @nodoc
abstract mixin class $ActionCopyWith<$Res>  {
  factory $ActionCopyWith(Action value, $Res Function(Action) _then) = _$ActionCopyWithImpl;
@useResult
$Res call({
 ActionMethod method, dynamic data, String id
});




}
/// @nodoc
class _$ActionCopyWithImpl<$Res>
    implements $ActionCopyWith<$Res> {
  _$ActionCopyWithImpl(this._self, this._then);

  final Action _self;
  final $Res Function(Action) _then;

/// Create a copy of Action
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? method = null,Object? data = freezed,Object? id = null,}) {
  return _then(_self.copyWith(
method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as ActionMethod,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Action].
extension ActionPatterns on Action {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Action value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Action() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Action value)  $default,){
final _that = this;
switch (_that) {
case _Action():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Action value)?  $default,){
final _that = this;
switch (_that) {
case _Action() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ActionMethod method,  dynamic data,  String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Action() when $default != null:
return $default(_that.method,_that.data,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ActionMethod method,  dynamic data,  String id)  $default,) {final _that = this;
switch (_that) {
case _Action():
return $default(_that.method,_that.data,_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ActionMethod method,  dynamic data,  String id)?  $default,) {final _that = this;
switch (_that) {
case _Action() when $default != null:
return $default(_that.method,_that.data,_that.id);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Action implements Action {
  const _Action({required this.method, required this.data, required this.id});
  factory _Action.fromJson(Map<String, dynamic> json) => _$ActionFromJson(json);

@override final  ActionMethod method;
@override final  dynamic data;
@override final  String id;

/// Create a copy of Action
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionCopyWith<_Action> get copyWith => __$ActionCopyWithImpl<_Action>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Action&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,method,const DeepCollectionEquality().hash(data),id);

@override
String toString() {
  return 'Action(method: $method, data: $data, id: $id)';
}


}

/// @nodoc
abstract mixin class _$ActionCopyWith<$Res> implements $ActionCopyWith<$Res> {
  factory _$ActionCopyWith(_Action value, $Res Function(_Action) _then) = __$ActionCopyWithImpl;
@override @useResult
$Res call({
 ActionMethod method, dynamic data, String id
});




}
/// @nodoc
class __$ActionCopyWithImpl<$Res>
    implements _$ActionCopyWith<$Res> {
  __$ActionCopyWithImpl(this._self, this._then);

  final _Action _self;
  final $Res Function(_Action) _then;

/// Create a copy of Action
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? method = null,Object? data = freezed,Object? id = null,}) {
  return _then(_Action(
method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as ActionMethod,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ProxiesData {

 Map<String, dynamic> get proxies; List<String> get all; int get generation; List<ProxyGroupSnapshot> get groups; Map<String, ProxyNodeSnapshot> get nodesById;
/// Create a copy of ProxiesData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxiesDataCopyWith<ProxiesData> get copyWith => _$ProxiesDataCopyWithImpl<ProxiesData>(this as ProxiesData, _$identity);

  /// Serializes this ProxiesData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxiesData&&const DeepCollectionEquality().equals(other.proxies, proxies)&&const DeepCollectionEquality().equals(other.all, all)&&(identical(other.generation, generation) || other.generation == generation)&&const DeepCollectionEquality().equals(other.groups, groups)&&const DeepCollectionEquality().equals(other.nodesById, nodesById));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(proxies),const DeepCollectionEquality().hash(all),generation,const DeepCollectionEquality().hash(groups),const DeepCollectionEquality().hash(nodesById));

@override
String toString() {
  return 'ProxiesData(proxies: $proxies, all: $all, generation: $generation, groups: $groups, nodesById: $nodesById)';
}


}

/// @nodoc
abstract mixin class $ProxiesDataCopyWith<$Res>  {
  factory $ProxiesDataCopyWith(ProxiesData value, $Res Function(ProxiesData) _then) = _$ProxiesDataCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> proxies, List<String> all, int generation, List<ProxyGroupSnapshot> groups, Map<String, ProxyNodeSnapshot> nodesById
});




}
/// @nodoc
class _$ProxiesDataCopyWithImpl<$Res>
    implements $ProxiesDataCopyWith<$Res> {
  _$ProxiesDataCopyWithImpl(this._self, this._then);

  final ProxiesData _self;
  final $Res Function(ProxiesData) _then;

/// Create a copy of ProxiesData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? proxies = null,Object? all = null,Object? generation = null,Object? groups = null,Object? nodesById = null,}) {
  return _then(_self.copyWith(
proxies: null == proxies ? _self.proxies : proxies // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,all: null == all ? _self.all : all // ignore: cast_nullable_to_non_nullable
as List<String>,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as List<ProxyGroupSnapshot>,nodesById: null == nodesById ? _self.nodesById : nodesById // ignore: cast_nullable_to_non_nullable
as Map<String, ProxyNodeSnapshot>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxiesData].
extension ProxiesDataPatterns on ProxiesData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxiesData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxiesData() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxiesData value)  $default,){
final _that = this;
switch (_that) {
case _ProxiesData():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxiesData value)?  $default,){
final _that = this;
switch (_that) {
case _ProxiesData() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic> proxies,  List<String> all,  int generation,  List<ProxyGroupSnapshot> groups,  Map<String, ProxyNodeSnapshot> nodesById)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxiesData() when $default != null:
return $default(_that.proxies,_that.all,_that.generation,_that.groups,_that.nodesById);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic> proxies,  List<String> all,  int generation,  List<ProxyGroupSnapshot> groups,  Map<String, ProxyNodeSnapshot> nodesById)  $default,) {final _that = this;
switch (_that) {
case _ProxiesData():
return $default(_that.proxies,_that.all,_that.generation,_that.groups,_that.nodesById);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic> proxies,  List<String> all,  int generation,  List<ProxyGroupSnapshot> groups,  Map<String, ProxyNodeSnapshot> nodesById)?  $default,) {final _that = this;
switch (_that) {
case _ProxiesData() when $default != null:
return $default(_that.proxies,_that.all,_that.generation,_that.groups,_that.nodesById);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxiesData implements ProxiesData {
  const _ProxiesData({final  Map<String, dynamic> proxies = const {}, final  List<String> all = const [], this.generation = 0, final  List<ProxyGroupSnapshot> groups = const [], final  Map<String, ProxyNodeSnapshot> nodesById = const {}}): _proxies = proxies,_all = all,_groups = groups,_nodesById = nodesById;
  factory _ProxiesData.fromJson(Map<String, dynamic> json) => _$ProxiesDataFromJson(json);

 final  Map<String, dynamic> _proxies;
@override@JsonKey() Map<String, dynamic> get proxies {
  if (_proxies is EqualUnmodifiableMapView) return _proxies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_proxies);
}

 final  List<String> _all;
@override@JsonKey() List<String> get all {
  if (_all is EqualUnmodifiableListView) return _all;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_all);
}

@override@JsonKey() final  int generation;
 final  List<ProxyGroupSnapshot> _groups;
@override@JsonKey() List<ProxyGroupSnapshot> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}

 final  Map<String, ProxyNodeSnapshot> _nodesById;
@override@JsonKey() Map<String, ProxyNodeSnapshot> get nodesById {
  if (_nodesById is EqualUnmodifiableMapView) return _nodesById;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_nodesById);
}


/// Create a copy of ProxiesData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxiesDataCopyWith<_ProxiesData> get copyWith => __$ProxiesDataCopyWithImpl<_ProxiesData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxiesDataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxiesData&&const DeepCollectionEquality().equals(other._proxies, _proxies)&&const DeepCollectionEquality().equals(other._all, _all)&&(identical(other.generation, generation) || other.generation == generation)&&const DeepCollectionEquality().equals(other._groups, _groups)&&const DeepCollectionEquality().equals(other._nodesById, _nodesById));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_proxies),const DeepCollectionEquality().hash(_all),generation,const DeepCollectionEquality().hash(_groups),const DeepCollectionEquality().hash(_nodesById));

@override
String toString() {
  return 'ProxiesData(proxies: $proxies, all: $all, generation: $generation, groups: $groups, nodesById: $nodesById)';
}


}

/// @nodoc
abstract mixin class _$ProxiesDataCopyWith<$Res> implements $ProxiesDataCopyWith<$Res> {
  factory _$ProxiesDataCopyWith(_ProxiesData value, $Res Function(_ProxiesData) _then) = __$ProxiesDataCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> proxies, List<String> all, int generation, List<ProxyGroupSnapshot> groups, Map<String, ProxyNodeSnapshot> nodesById
});




}
/// @nodoc
class __$ProxiesDataCopyWithImpl<$Res>
    implements _$ProxiesDataCopyWith<$Res> {
  __$ProxiesDataCopyWithImpl(this._self, this._then);

  final _ProxiesData _self;
  final $Res Function(_ProxiesData) _then;

/// Create a copy of ProxiesData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? proxies = null,Object? all = null,Object? generation = null,Object? groups = null,Object? nodesById = null,}) {
  return _then(_ProxiesData(
proxies: null == proxies ? _self._proxies : proxies // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,all: null == all ? _self._all : all // ignore: cast_nullable_to_non_nullable
as List<String>,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<ProxyGroupSnapshot>,nodesById: null == nodesById ? _self._nodesById : nodesById // ignore: cast_nullable_to_non_nullable
as Map<String, ProxyNodeSnapshot>,
  ));
}


}


/// @nodoc
mixin _$ProxyGroupSnapshot {

 String get id; String get name; String get type; String get nowId; List<String> get memberIds;
/// Create a copy of ProxyGroupSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyGroupSnapshotCopyWith<ProxyGroupSnapshot> get copyWith => _$ProxyGroupSnapshotCopyWithImpl<ProxyGroupSnapshot>(this as ProxyGroupSnapshot, _$identity);

  /// Serializes this ProxyGroupSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyGroupSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.nowId, nowId) || other.nowId == nowId)&&const DeepCollectionEquality().equals(other.memberIds, memberIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,type,nowId,const DeepCollectionEquality().hash(memberIds));

@override
String toString() {
  return 'ProxyGroupSnapshot(id: $id, name: $name, type: $type, nowId: $nowId, memberIds: $memberIds)';
}


}

/// @nodoc
abstract mixin class $ProxyGroupSnapshotCopyWith<$Res>  {
  factory $ProxyGroupSnapshotCopyWith(ProxyGroupSnapshot value, $Res Function(ProxyGroupSnapshot) _then) = _$ProxyGroupSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, String name, String type, String nowId, List<String> memberIds
});




}
/// @nodoc
class _$ProxyGroupSnapshotCopyWithImpl<$Res>
    implements $ProxyGroupSnapshotCopyWith<$Res> {
  _$ProxyGroupSnapshotCopyWithImpl(this._self, this._then);

  final ProxyGroupSnapshot _self;
  final $Res Function(ProxyGroupSnapshot) _then;

/// Create a copy of ProxyGroupSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? type = null,Object? nowId = null,Object? memberIds = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,nowId: null == nowId ? _self.nowId : nowId // ignore: cast_nullable_to_non_nullable
as String,memberIds: null == memberIds ? _self.memberIds : memberIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxyGroupSnapshot].
extension ProxyGroupSnapshotPatterns on ProxyGroupSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyGroupSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyGroupSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyGroupSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ProxyGroupSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyGroupSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyGroupSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String type,  String nowId,  List<String> memberIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyGroupSnapshot() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.nowId,_that.memberIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String type,  String nowId,  List<String> memberIds)  $default,) {final _that = this;
switch (_that) {
case _ProxyGroupSnapshot():
return $default(_that.id,_that.name,_that.type,_that.nowId,_that.memberIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String type,  String nowId,  List<String> memberIds)?  $default,) {final _that = this;
switch (_that) {
case _ProxyGroupSnapshot() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.nowId,_that.memberIds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyGroupSnapshot implements ProxyGroupSnapshot {
  const _ProxyGroupSnapshot({required this.id, required this.name, required this.type, this.nowId = '', final  List<String> memberIds = const []}): _memberIds = memberIds;
  factory _ProxyGroupSnapshot.fromJson(Map<String, dynamic> json) => _$ProxyGroupSnapshotFromJson(json);

@override final  String id;
@override final  String name;
@override final  String type;
@override@JsonKey() final  String nowId;
 final  List<String> _memberIds;
@override@JsonKey() List<String> get memberIds {
  if (_memberIds is EqualUnmodifiableListView) return _memberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_memberIds);
}


/// Create a copy of ProxyGroupSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyGroupSnapshotCopyWith<_ProxyGroupSnapshot> get copyWith => __$ProxyGroupSnapshotCopyWithImpl<_ProxyGroupSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyGroupSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyGroupSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.nowId, nowId) || other.nowId == nowId)&&const DeepCollectionEquality().equals(other._memberIds, _memberIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,type,nowId,const DeepCollectionEquality().hash(_memberIds));

@override
String toString() {
  return 'ProxyGroupSnapshot(id: $id, name: $name, type: $type, nowId: $nowId, memberIds: $memberIds)';
}


}

/// @nodoc
abstract mixin class _$ProxyGroupSnapshotCopyWith<$Res> implements $ProxyGroupSnapshotCopyWith<$Res> {
  factory _$ProxyGroupSnapshotCopyWith(_ProxyGroupSnapshot value, $Res Function(_ProxyGroupSnapshot) _then) = __$ProxyGroupSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String type, String nowId, List<String> memberIds
});




}
/// @nodoc
class __$ProxyGroupSnapshotCopyWithImpl<$Res>
    implements _$ProxyGroupSnapshotCopyWith<$Res> {
  __$ProxyGroupSnapshotCopyWithImpl(this._self, this._then);

  final _ProxyGroupSnapshot _self;
  final $Res Function(_ProxyGroupSnapshot) _then;

/// Create a copy of ProxyGroupSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? type = null,Object? nowId = null,Object? memberIds = null,}) {
  return _then(_ProxyGroupSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,nowId: null == nowId ? _self.nowId : nowId // ignore: cast_nullable_to_non_nullable
as String,memberIds: null == memberIds ? _self._memberIds : memberIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$ProxyNodeSnapshot {

 String get id; String get stableKey; String get name; String get type; String get providerName;
/// Create a copy of ProxyNodeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyNodeSnapshotCopyWith<ProxyNodeSnapshot> get copyWith => _$ProxyNodeSnapshotCopyWithImpl<ProxyNodeSnapshot>(this as ProxyNodeSnapshot, _$identity);

  /// Serializes this ProxyNodeSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyNodeSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.stableKey, stableKey) || other.stableKey == stableKey)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.providerName, providerName) || other.providerName == providerName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,stableKey,name,type,providerName);

@override
String toString() {
  return 'ProxyNodeSnapshot(id: $id, stableKey: $stableKey, name: $name, type: $type, providerName: $providerName)';
}


}

/// @nodoc
abstract mixin class $ProxyNodeSnapshotCopyWith<$Res>  {
  factory $ProxyNodeSnapshotCopyWith(ProxyNodeSnapshot value, $Res Function(ProxyNodeSnapshot) _then) = _$ProxyNodeSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, String stableKey, String name, String type, String providerName
});




}
/// @nodoc
class _$ProxyNodeSnapshotCopyWithImpl<$Res>
    implements $ProxyNodeSnapshotCopyWith<$Res> {
  _$ProxyNodeSnapshotCopyWithImpl(this._self, this._then);

  final ProxyNodeSnapshot _self;
  final $Res Function(ProxyNodeSnapshot) _then;

/// Create a copy of ProxyNodeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? stableKey = null,Object? name = null,Object? type = null,Object? providerName = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,stableKey: null == stableKey ? _self.stableKey : stableKey // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,providerName: null == providerName ? _self.providerName : providerName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxyNodeSnapshot].
extension ProxyNodeSnapshotPatterns on ProxyNodeSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyNodeSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyNodeSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyNodeSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ProxyNodeSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyNodeSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyNodeSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String stableKey,  String name,  String type,  String providerName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyNodeSnapshot() when $default != null:
return $default(_that.id,_that.stableKey,_that.name,_that.type,_that.providerName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String stableKey,  String name,  String type,  String providerName)  $default,) {final _that = this;
switch (_that) {
case _ProxyNodeSnapshot():
return $default(_that.id,_that.stableKey,_that.name,_that.type,_that.providerName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String stableKey,  String name,  String type,  String providerName)?  $default,) {final _that = this;
switch (_that) {
case _ProxyNodeSnapshot() when $default != null:
return $default(_that.id,_that.stableKey,_that.name,_that.type,_that.providerName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyNodeSnapshot implements ProxyNodeSnapshot {
  const _ProxyNodeSnapshot({required this.id, required this.stableKey, required this.name, required this.type, this.providerName = ''});
  factory _ProxyNodeSnapshot.fromJson(Map<String, dynamic> json) => _$ProxyNodeSnapshotFromJson(json);

@override final  String id;
@override final  String stableKey;
@override final  String name;
@override final  String type;
@override@JsonKey() final  String providerName;

/// Create a copy of ProxyNodeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyNodeSnapshotCopyWith<_ProxyNodeSnapshot> get copyWith => __$ProxyNodeSnapshotCopyWithImpl<_ProxyNodeSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyNodeSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyNodeSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.stableKey, stableKey) || other.stableKey == stableKey)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.providerName, providerName) || other.providerName == providerName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,stableKey,name,type,providerName);

@override
String toString() {
  return 'ProxyNodeSnapshot(id: $id, stableKey: $stableKey, name: $name, type: $type, providerName: $providerName)';
}


}

/// @nodoc
abstract mixin class _$ProxyNodeSnapshotCopyWith<$Res> implements $ProxyNodeSnapshotCopyWith<$Res> {
  factory _$ProxyNodeSnapshotCopyWith(_ProxyNodeSnapshot value, $Res Function(_ProxyNodeSnapshot) _then) = __$ProxyNodeSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, String stableKey, String name, String type, String providerName
});




}
/// @nodoc
class __$ProxyNodeSnapshotCopyWithImpl<$Res>
    implements _$ProxyNodeSnapshotCopyWith<$Res> {
  __$ProxyNodeSnapshotCopyWithImpl(this._self, this._then);

  final _ProxyNodeSnapshot _self;
  final $Res Function(_ProxyNodeSnapshot) _then;

/// Create a copy of ProxyNodeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? stableKey = null,Object? name = null,Object? type = null,Object? providerName = null,}) {
  return _then(_ProxyNodeSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,stableKey: null == stableKey ? _self.stableKey : stableKey // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,providerName: null == providerName ? _self.providerName : providerName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ProxyServerGeoParams {

 int get generation; int get networkRevision; String get requestId; bool get all; List<String> get memberIds;
/// Create a copy of ProxyServerGeoParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyServerGeoParamsCopyWith<ProxyServerGeoParams> get copyWith => _$ProxyServerGeoParamsCopyWithImpl<ProxyServerGeoParams>(this as ProxyServerGeoParams, _$identity);

  /// Serializes this ProxyServerGeoParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyServerGeoParams&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.networkRevision, networkRevision) || other.networkRevision == networkRevision)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.all, all) || other.all == all)&&const DeepCollectionEquality().equals(other.memberIds, memberIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,networkRevision,requestId,all,const DeepCollectionEquality().hash(memberIds));

@override
String toString() {
  return 'ProxyServerGeoParams(generation: $generation, networkRevision: $networkRevision, requestId: $requestId, all: $all, memberIds: $memberIds)';
}


}

/// @nodoc
abstract mixin class $ProxyServerGeoParamsCopyWith<$Res>  {
  factory $ProxyServerGeoParamsCopyWith(ProxyServerGeoParams value, $Res Function(ProxyServerGeoParams) _then) = _$ProxyServerGeoParamsCopyWithImpl;
@useResult
$Res call({
 int generation, int networkRevision, String requestId, bool all, List<String> memberIds
});




}
/// @nodoc
class _$ProxyServerGeoParamsCopyWithImpl<$Res>
    implements $ProxyServerGeoParamsCopyWith<$Res> {
  _$ProxyServerGeoParamsCopyWithImpl(this._self, this._then);

  final ProxyServerGeoParams _self;
  final $Res Function(ProxyServerGeoParams) _then;

/// Create a copy of ProxyServerGeoParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? networkRevision = null,Object? requestId = null,Object? all = null,Object? memberIds = null,}) {
  return _then(_self.copyWith(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,networkRevision: null == networkRevision ? _self.networkRevision : networkRevision // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,all: null == all ? _self.all : all // ignore: cast_nullable_to_non_nullable
as bool,memberIds: null == memberIds ? _self.memberIds : memberIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxyServerGeoParams].
extension ProxyServerGeoParamsPatterns on ProxyServerGeoParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyServerGeoParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyServerGeoParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyServerGeoParams value)  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeoParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyServerGeoParams value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeoParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  int networkRevision,  String requestId,  bool all,  List<String> memberIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyServerGeoParams() when $default != null:
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.all,_that.memberIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  int networkRevision,  String requestId,  bool all,  List<String> memberIds)  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeoParams():
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.all,_that.memberIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  int networkRevision,  String requestId,  bool all,  List<String> memberIds)?  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeoParams() when $default != null:
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.all,_that.memberIds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyServerGeoParams implements ProxyServerGeoParams {
  const _ProxyServerGeoParams({required this.generation, this.networkRevision = 0, this.requestId = '', this.all = false, final  List<String> memberIds = const []}): _memberIds = memberIds;
  factory _ProxyServerGeoParams.fromJson(Map<String, dynamic> json) => _$ProxyServerGeoParamsFromJson(json);

@override final  int generation;
@override@JsonKey() final  int networkRevision;
@override@JsonKey() final  String requestId;
@override@JsonKey() final  bool all;
 final  List<String> _memberIds;
@override@JsonKey() List<String> get memberIds {
  if (_memberIds is EqualUnmodifiableListView) return _memberIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_memberIds);
}


/// Create a copy of ProxyServerGeoParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyServerGeoParamsCopyWith<_ProxyServerGeoParams> get copyWith => __$ProxyServerGeoParamsCopyWithImpl<_ProxyServerGeoParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyServerGeoParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyServerGeoParams&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.networkRevision, networkRevision) || other.networkRevision == networkRevision)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.all, all) || other.all == all)&&const DeepCollectionEquality().equals(other._memberIds, _memberIds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,networkRevision,requestId,all,const DeepCollectionEquality().hash(_memberIds));

@override
String toString() {
  return 'ProxyServerGeoParams(generation: $generation, networkRevision: $networkRevision, requestId: $requestId, all: $all, memberIds: $memberIds)';
}


}

/// @nodoc
abstract mixin class _$ProxyServerGeoParamsCopyWith<$Res> implements $ProxyServerGeoParamsCopyWith<$Res> {
  factory _$ProxyServerGeoParamsCopyWith(_ProxyServerGeoParams value, $Res Function(_ProxyServerGeoParams) _then) = __$ProxyServerGeoParamsCopyWithImpl;
@override @useResult
$Res call({
 int generation, int networkRevision, String requestId, bool all, List<String> memberIds
});




}
/// @nodoc
class __$ProxyServerGeoParamsCopyWithImpl<$Res>
    implements _$ProxyServerGeoParamsCopyWith<$Res> {
  __$ProxyServerGeoParamsCopyWithImpl(this._self, this._then);

  final _ProxyServerGeoParams _self;
  final $Res Function(_ProxyServerGeoParams) _then;

/// Create a copy of ProxyServerGeoParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? networkRevision = null,Object? requestId = null,Object? all = null,Object? memberIds = null,}) {
  return _then(_ProxyServerGeoParams(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,networkRevision: null == networkRevision ? _self.networkRevision : networkRevision // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,all: null == all ? _self.all : all // ignore: cast_nullable_to_non_nullable
as bool,memberIds: null == memberIds ? _self._memberIds : memberIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$GeoDatabaseGeneration {

 int get country; int get asn;
/// Create a copy of GeoDatabaseGeneration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GeoDatabaseGenerationCopyWith<GeoDatabaseGeneration> get copyWith => _$GeoDatabaseGenerationCopyWithImpl<GeoDatabaseGeneration>(this as GeoDatabaseGeneration, _$identity);

  /// Serializes this GeoDatabaseGeneration to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GeoDatabaseGeneration&&(identical(other.country, country) || other.country == country)&&(identical(other.asn, asn) || other.asn == asn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,country,asn);

@override
String toString() {
  return 'GeoDatabaseGeneration(country: $country, asn: $asn)';
}


}

/// @nodoc
abstract mixin class $GeoDatabaseGenerationCopyWith<$Res>  {
  factory $GeoDatabaseGenerationCopyWith(GeoDatabaseGeneration value, $Res Function(GeoDatabaseGeneration) _then) = _$GeoDatabaseGenerationCopyWithImpl;
@useResult
$Res call({
 int country, int asn
});




}
/// @nodoc
class _$GeoDatabaseGenerationCopyWithImpl<$Res>
    implements $GeoDatabaseGenerationCopyWith<$Res> {
  _$GeoDatabaseGenerationCopyWithImpl(this._self, this._then);

  final GeoDatabaseGeneration _self;
  final $Res Function(GeoDatabaseGeneration) _then;

/// Create a copy of GeoDatabaseGeneration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? country = null,Object? asn = null,}) {
  return _then(_self.copyWith(
country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as int,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GeoDatabaseGeneration].
extension GeoDatabaseGenerationPatterns on GeoDatabaseGeneration {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GeoDatabaseGeneration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GeoDatabaseGeneration() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GeoDatabaseGeneration value)  $default,){
final _that = this;
switch (_that) {
case _GeoDatabaseGeneration():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GeoDatabaseGeneration value)?  $default,){
final _that = this;
switch (_that) {
case _GeoDatabaseGeneration() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int country,  int asn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GeoDatabaseGeneration() when $default != null:
return $default(_that.country,_that.asn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int country,  int asn)  $default,) {final _that = this;
switch (_that) {
case _GeoDatabaseGeneration():
return $default(_that.country,_that.asn);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int country,  int asn)?  $default,) {final _that = this;
switch (_that) {
case _GeoDatabaseGeneration() when $default != null:
return $default(_that.country,_that.asn);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GeoDatabaseGeneration implements GeoDatabaseGeneration {
  const _GeoDatabaseGeneration({this.country = 0, this.asn = 0});
  factory _GeoDatabaseGeneration.fromJson(Map<String, dynamic> json) => _$GeoDatabaseGenerationFromJson(json);

@override@JsonKey() final  int country;
@override@JsonKey() final  int asn;

/// Create a copy of GeoDatabaseGeneration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GeoDatabaseGenerationCopyWith<_GeoDatabaseGeneration> get copyWith => __$GeoDatabaseGenerationCopyWithImpl<_GeoDatabaseGeneration>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GeoDatabaseGenerationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GeoDatabaseGeneration&&(identical(other.country, country) || other.country == country)&&(identical(other.asn, asn) || other.asn == asn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,country,asn);

@override
String toString() {
  return 'GeoDatabaseGeneration(country: $country, asn: $asn)';
}


}

/// @nodoc
abstract mixin class _$GeoDatabaseGenerationCopyWith<$Res> implements $GeoDatabaseGenerationCopyWith<$Res> {
  factory _$GeoDatabaseGenerationCopyWith(_GeoDatabaseGeneration value, $Res Function(_GeoDatabaseGeneration) _then) = __$GeoDatabaseGenerationCopyWithImpl;
@override @useResult
$Res call({
 int country, int asn
});




}
/// @nodoc
class __$GeoDatabaseGenerationCopyWithImpl<$Res>
    implements _$GeoDatabaseGenerationCopyWith<$Res> {
  __$GeoDatabaseGenerationCopyWithImpl(this._self, this._then);

  final _GeoDatabaseGeneration _self;
  final $Res Function(_GeoDatabaseGeneration) _then;

/// Create a copy of GeoDatabaseGeneration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? country = null,Object? asn = null,}) {
  return _then(_GeoDatabaseGeneration(
country: null == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as int,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ProxyGeoAddress {

 String get ip; String get countryCode; String get asn; String get aso;
/// Create a copy of ProxyGeoAddress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyGeoAddressCopyWith<ProxyGeoAddress> get copyWith => _$ProxyGeoAddressCopyWithImpl<ProxyGeoAddress>(this as ProxyGeoAddress, _$identity);

  /// Serializes this ProxyGeoAddress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyGeoAddress&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.asn, asn) || other.asn == asn)&&(identical(other.aso, aso) || other.aso == aso));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ip,countryCode,asn,aso);

@override
String toString() {
  return 'ProxyGeoAddress(ip: $ip, countryCode: $countryCode, asn: $asn, aso: $aso)';
}


}

/// @nodoc
abstract mixin class $ProxyGeoAddressCopyWith<$Res>  {
  factory $ProxyGeoAddressCopyWith(ProxyGeoAddress value, $Res Function(ProxyGeoAddress) _then) = _$ProxyGeoAddressCopyWithImpl;
@useResult
$Res call({
 String ip, String countryCode, String asn, String aso
});




}
/// @nodoc
class _$ProxyGeoAddressCopyWithImpl<$Res>
    implements $ProxyGeoAddressCopyWith<$Res> {
  _$ProxyGeoAddressCopyWithImpl(this._self, this._then);

  final ProxyGeoAddress _self;
  final $Res Function(ProxyGeoAddress) _then;

/// Create a copy of ProxyGeoAddress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ip = null,Object? countryCode = null,Object? asn = null,Object? aso = null,}) {
  return _then(_self.copyWith(
ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as String,aso: null == aso ? _self.aso : aso // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxyGeoAddress].
extension ProxyGeoAddressPatterns on ProxyGeoAddress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyGeoAddress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyGeoAddress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyGeoAddress value)  $default,){
final _that = this;
switch (_that) {
case _ProxyGeoAddress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyGeoAddress value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyGeoAddress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ip,  String countryCode,  String asn,  String aso)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyGeoAddress() when $default != null:
return $default(_that.ip,_that.countryCode,_that.asn,_that.aso);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ip,  String countryCode,  String asn,  String aso)  $default,) {final _that = this;
switch (_that) {
case _ProxyGeoAddress():
return $default(_that.ip,_that.countryCode,_that.asn,_that.aso);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ip,  String countryCode,  String asn,  String aso)?  $default,) {final _that = this;
switch (_that) {
case _ProxyGeoAddress() when $default != null:
return $default(_that.ip,_that.countryCode,_that.asn,_that.aso);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyGeoAddress implements ProxyGeoAddress {
  const _ProxyGeoAddress({required this.ip, this.countryCode = '', this.asn = '', this.aso = ''});
  factory _ProxyGeoAddress.fromJson(Map<String, dynamic> json) => _$ProxyGeoAddressFromJson(json);

@override final  String ip;
@override@JsonKey() final  String countryCode;
@override@JsonKey() final  String asn;
@override@JsonKey() final  String aso;

/// Create a copy of ProxyGeoAddress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyGeoAddressCopyWith<_ProxyGeoAddress> get copyWith => __$ProxyGeoAddressCopyWithImpl<_ProxyGeoAddress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyGeoAddressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyGeoAddress&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.asn, asn) || other.asn == asn)&&(identical(other.aso, aso) || other.aso == aso));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ip,countryCode,asn,aso);

@override
String toString() {
  return 'ProxyGeoAddress(ip: $ip, countryCode: $countryCode, asn: $asn, aso: $aso)';
}


}

/// @nodoc
abstract mixin class _$ProxyGeoAddressCopyWith<$Res> implements $ProxyGeoAddressCopyWith<$Res> {
  factory _$ProxyGeoAddressCopyWith(_ProxyGeoAddress value, $Res Function(_ProxyGeoAddress) _then) = __$ProxyGeoAddressCopyWithImpl;
@override @useResult
$Res call({
 String ip, String countryCode, String asn, String aso
});




}
/// @nodoc
class __$ProxyGeoAddressCopyWithImpl<$Res>
    implements _$ProxyGeoAddressCopyWith<$Res> {
  __$ProxyGeoAddressCopyWithImpl(this._self, this._then);

  final _ProxyGeoAddress _self;
  final $Res Function(_ProxyGeoAddress) _then;

/// Create a copy of ProxyGeoAddress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ip = null,Object? countryCode = null,Object? asn = null,Object? aso = null,}) {
  return _then(_ProxyGeoAddress(
ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as String,aso: null == aso ? _self.aso : aso // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ProxyServerGeo {

 String get memberId; String get serverHost; String get source; String get status; bool get multiRegion; List<ProxyGeoAddress> get addresses;
/// Create a copy of ProxyServerGeo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyServerGeoCopyWith<ProxyServerGeo> get copyWith => _$ProxyServerGeoCopyWithImpl<ProxyServerGeo>(this as ProxyServerGeo, _$identity);

  /// Serializes this ProxyServerGeo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyServerGeo&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.serverHost, serverHost) || other.serverHost == serverHost)&&(identical(other.source, source) || other.source == source)&&(identical(other.status, status) || other.status == status)&&(identical(other.multiRegion, multiRegion) || other.multiRegion == multiRegion)&&const DeepCollectionEquality().equals(other.addresses, addresses));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,serverHost,source,status,multiRegion,const DeepCollectionEquality().hash(addresses));

@override
String toString() {
  return 'ProxyServerGeo(memberId: $memberId, serverHost: $serverHost, source: $source, status: $status, multiRegion: $multiRegion, addresses: $addresses)';
}


}

/// @nodoc
abstract mixin class $ProxyServerGeoCopyWith<$Res>  {
  factory $ProxyServerGeoCopyWith(ProxyServerGeo value, $Res Function(ProxyServerGeo) _then) = _$ProxyServerGeoCopyWithImpl;
@useResult
$Res call({
 String memberId, String serverHost, String source, String status, bool multiRegion, List<ProxyGeoAddress> addresses
});




}
/// @nodoc
class _$ProxyServerGeoCopyWithImpl<$Res>
    implements $ProxyServerGeoCopyWith<$Res> {
  _$ProxyServerGeoCopyWithImpl(this._self, this._then);

  final ProxyServerGeo _self;
  final $Res Function(ProxyServerGeo) _then;

/// Create a copy of ProxyServerGeo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? memberId = null,Object? serverHost = null,Object? source = null,Object? status = null,Object? multiRegion = null,Object? addresses = null,}) {
  return _then(_self.copyWith(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,serverHost: null == serverHost ? _self.serverHost : serverHost // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,multiRegion: null == multiRegion ? _self.multiRegion : multiRegion // ignore: cast_nullable_to_non_nullable
as bool,addresses: null == addresses ? _self.addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<ProxyGeoAddress>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProxyServerGeo].
extension ProxyServerGeoPatterns on ProxyServerGeo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyServerGeo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyServerGeo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyServerGeo value)  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyServerGeo value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String memberId,  String serverHost,  String source,  String status,  bool multiRegion,  List<ProxyGeoAddress> addresses)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyServerGeo() when $default != null:
return $default(_that.memberId,_that.serverHost,_that.source,_that.status,_that.multiRegion,_that.addresses);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String memberId,  String serverHost,  String source,  String status,  bool multiRegion,  List<ProxyGeoAddress> addresses)  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeo():
return $default(_that.memberId,_that.serverHost,_that.source,_that.status,_that.multiRegion,_that.addresses);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String memberId,  String serverHost,  String source,  String status,  bool multiRegion,  List<ProxyGeoAddress> addresses)?  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeo() when $default != null:
return $default(_that.memberId,_that.serverHost,_that.source,_that.status,_that.multiRegion,_that.addresses);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyServerGeo implements ProxyServerGeo {
  const _ProxyServerGeo({required this.memberId, this.serverHost = '', this.source = '', this.status = '', this.multiRegion = false, final  List<ProxyGeoAddress> addresses = const []}): _addresses = addresses;
  factory _ProxyServerGeo.fromJson(Map<String, dynamic> json) => _$ProxyServerGeoFromJson(json);

@override final  String memberId;
@override@JsonKey() final  String serverHost;
@override@JsonKey() final  String source;
@override@JsonKey() final  String status;
@override@JsonKey() final  bool multiRegion;
 final  List<ProxyGeoAddress> _addresses;
@override@JsonKey() List<ProxyGeoAddress> get addresses {
  if (_addresses is EqualUnmodifiableListView) return _addresses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_addresses);
}


/// Create a copy of ProxyServerGeo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyServerGeoCopyWith<_ProxyServerGeo> get copyWith => __$ProxyServerGeoCopyWithImpl<_ProxyServerGeo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyServerGeoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyServerGeo&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.serverHost, serverHost) || other.serverHost == serverHost)&&(identical(other.source, source) || other.source == source)&&(identical(other.status, status) || other.status == status)&&(identical(other.multiRegion, multiRegion) || other.multiRegion == multiRegion)&&const DeepCollectionEquality().equals(other._addresses, _addresses));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,memberId,serverHost,source,status,multiRegion,const DeepCollectionEquality().hash(_addresses));

@override
String toString() {
  return 'ProxyServerGeo(memberId: $memberId, serverHost: $serverHost, source: $source, status: $status, multiRegion: $multiRegion, addresses: $addresses)';
}


}

/// @nodoc
abstract mixin class _$ProxyServerGeoCopyWith<$Res> implements $ProxyServerGeoCopyWith<$Res> {
  factory _$ProxyServerGeoCopyWith(_ProxyServerGeo value, $Res Function(_ProxyServerGeo) _then) = __$ProxyServerGeoCopyWithImpl;
@override @useResult
$Res call({
 String memberId, String serverHost, String source, String status, bool multiRegion, List<ProxyGeoAddress> addresses
});




}
/// @nodoc
class __$ProxyServerGeoCopyWithImpl<$Res>
    implements _$ProxyServerGeoCopyWith<$Res> {
  __$ProxyServerGeoCopyWithImpl(this._self, this._then);

  final _ProxyServerGeo _self;
  final $Res Function(_ProxyServerGeo) _then;

/// Create a copy of ProxyServerGeo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? memberId = null,Object? serverHost = null,Object? source = null,Object? status = null,Object? multiRegion = null,Object? addresses = null,}) {
  return _then(_ProxyServerGeo(
memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,serverHost: null == serverHost ? _self.serverHost : serverHost // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,multiRegion: null == multiRegion ? _self.multiRegion : multiRegion // ignore: cast_nullable_to_non_nullable
as bool,addresses: null == addresses ? _self._addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<ProxyGeoAddress>,
  ));
}


}


/// @nodoc
mixin _$ProxyServerGeos {

 int get generation; String get requestId; bool get stale; GeoDatabaseGeneration get dbGeneration; Map<String, ProxyServerGeo> get members;
/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyServerGeosCopyWith<ProxyServerGeos> get copyWith => _$ProxyServerGeosCopyWithImpl<ProxyServerGeos>(this as ProxyServerGeos, _$identity);

  /// Serializes this ProxyServerGeos to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyServerGeos&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.dbGeneration, dbGeneration) || other.dbGeneration == dbGeneration)&&const DeepCollectionEquality().equals(other.members, members));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,requestId,stale,dbGeneration,const DeepCollectionEquality().hash(members));

@override
String toString() {
  return 'ProxyServerGeos(generation: $generation, requestId: $requestId, stale: $stale, dbGeneration: $dbGeneration, members: $members)';
}


}

/// @nodoc
abstract mixin class $ProxyServerGeosCopyWith<$Res>  {
  factory $ProxyServerGeosCopyWith(ProxyServerGeos value, $Res Function(ProxyServerGeos) _then) = _$ProxyServerGeosCopyWithImpl;
@useResult
$Res call({
 int generation, String requestId, bool stale, GeoDatabaseGeneration dbGeneration, Map<String, ProxyServerGeo> members
});


$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration;

}
/// @nodoc
class _$ProxyServerGeosCopyWithImpl<$Res>
    implements $ProxyServerGeosCopyWith<$Res> {
  _$ProxyServerGeosCopyWithImpl(this._self, this._then);

  final ProxyServerGeos _self;
  final $Res Function(ProxyServerGeos) _then;

/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? requestId = null,Object? stale = null,Object? dbGeneration = null,Object? members = null,}) {
  return _then(_self.copyWith(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,dbGeneration: null == dbGeneration ? _self.dbGeneration : dbGeneration // ignore: cast_nullable_to_non_nullable
as GeoDatabaseGeneration,members: null == members ? _self.members : members // ignore: cast_nullable_to_non_nullable
as Map<String, ProxyServerGeo>,
  ));
}
/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration {

  return $GeoDatabaseGenerationCopyWith<$Res>(_self.dbGeneration, (value) {
    return _then(_self.copyWith(dbGeneration: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProxyServerGeos].
extension ProxyServerGeosPatterns on ProxyServerGeos {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyServerGeos value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyServerGeos() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyServerGeos value)  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeos():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyServerGeos value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyServerGeos() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  String requestId,  bool stale,  GeoDatabaseGeneration dbGeneration,  Map<String, ProxyServerGeo> members)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyServerGeos() when $default != null:
return $default(_that.generation,_that.requestId,_that.stale,_that.dbGeneration,_that.members);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  String requestId,  bool stale,  GeoDatabaseGeneration dbGeneration,  Map<String, ProxyServerGeo> members)  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeos():
return $default(_that.generation,_that.requestId,_that.stale,_that.dbGeneration,_that.members);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  String requestId,  bool stale,  GeoDatabaseGeneration dbGeneration,  Map<String, ProxyServerGeo> members)?  $default,) {final _that = this;
switch (_that) {
case _ProxyServerGeos() when $default != null:
return $default(_that.generation,_that.requestId,_that.stale,_that.dbGeneration,_that.members);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyServerGeos implements ProxyServerGeos {
  const _ProxyServerGeos({required this.generation, this.requestId = '', this.stale = false, this.dbGeneration = const GeoDatabaseGeneration(), final  Map<String, ProxyServerGeo> members = const {}}): _members = members;
  factory _ProxyServerGeos.fromJson(Map<String, dynamic> json) => _$ProxyServerGeosFromJson(json);

@override final  int generation;
@override@JsonKey() final  String requestId;
@override@JsonKey() final  bool stale;
@override@JsonKey() final  GeoDatabaseGeneration dbGeneration;
 final  Map<String, ProxyServerGeo> _members;
@override@JsonKey() Map<String, ProxyServerGeo> get members {
  if (_members is EqualUnmodifiableMapView) return _members;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_members);
}


/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyServerGeosCopyWith<_ProxyServerGeos> get copyWith => __$ProxyServerGeosCopyWithImpl<_ProxyServerGeos>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyServerGeosToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyServerGeos&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.dbGeneration, dbGeneration) || other.dbGeneration == dbGeneration)&&const DeepCollectionEquality().equals(other._members, _members));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,requestId,stale,dbGeneration,const DeepCollectionEquality().hash(_members));

@override
String toString() {
  return 'ProxyServerGeos(generation: $generation, requestId: $requestId, stale: $stale, dbGeneration: $dbGeneration, members: $members)';
}


}

/// @nodoc
abstract mixin class _$ProxyServerGeosCopyWith<$Res> implements $ProxyServerGeosCopyWith<$Res> {
  factory _$ProxyServerGeosCopyWith(_ProxyServerGeos value, $Res Function(_ProxyServerGeos) _then) = __$ProxyServerGeosCopyWithImpl;
@override @useResult
$Res call({
 int generation, String requestId, bool stale, GeoDatabaseGeneration dbGeneration, Map<String, ProxyServerGeo> members
});


@override $GeoDatabaseGenerationCopyWith<$Res> get dbGeneration;

}
/// @nodoc
class __$ProxyServerGeosCopyWithImpl<$Res>
    implements _$ProxyServerGeosCopyWith<$Res> {
  __$ProxyServerGeosCopyWithImpl(this._self, this._then);

  final _ProxyServerGeos _self;
  final $Res Function(_ProxyServerGeos) _then;

/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? requestId = null,Object? stale = null,Object? dbGeneration = null,Object? members = null,}) {
  return _then(_ProxyServerGeos(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,dbGeneration: null == dbGeneration ? _self.dbGeneration : dbGeneration // ignore: cast_nullable_to_non_nullable
as GeoDatabaseGeneration,members: null == members ? _self._members : members // ignore: cast_nullable_to_non_nullable
as Map<String, ProxyServerGeo>,
  ));
}

/// Create a copy of ProxyServerGeos
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration {

  return $GeoDatabaseGenerationCopyWith<$Res>(_self.dbGeneration, (value) {
    return _then(_self.copyWith(dbGeneration: value));
  });
}
}


/// @nodoc
mixin _$ProbeProxyExitParams {

 int get generation; int get networkRevision; String get requestId; String get groupId; String get memberId;
/// Create a copy of ProbeProxyExitParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProbeProxyExitParamsCopyWith<ProbeProxyExitParams> get copyWith => _$ProbeProxyExitParamsCopyWithImpl<ProbeProxyExitParams>(this as ProbeProxyExitParams, _$identity);

  /// Serializes this ProbeProxyExitParams to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProbeProxyExitParams&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.networkRevision, networkRevision) || other.networkRevision == networkRevision)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,networkRevision,requestId,groupId,memberId);

@override
String toString() {
  return 'ProbeProxyExitParams(generation: $generation, networkRevision: $networkRevision, requestId: $requestId, groupId: $groupId, memberId: $memberId)';
}


}

/// @nodoc
abstract mixin class $ProbeProxyExitParamsCopyWith<$Res>  {
  factory $ProbeProxyExitParamsCopyWith(ProbeProxyExitParams value, $Res Function(ProbeProxyExitParams) _then) = _$ProbeProxyExitParamsCopyWithImpl;
@useResult
$Res call({
 int generation, int networkRevision, String requestId, String groupId, String memberId
});




}
/// @nodoc
class _$ProbeProxyExitParamsCopyWithImpl<$Res>
    implements $ProbeProxyExitParamsCopyWith<$Res> {
  _$ProbeProxyExitParamsCopyWithImpl(this._self, this._then);

  final ProbeProxyExitParams _self;
  final $Res Function(ProbeProxyExitParams) _then;

/// Create a copy of ProbeProxyExitParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? networkRevision = null,Object? requestId = null,Object? groupId = null,Object? memberId = null,}) {
  return _then(_self.copyWith(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,networkRevision: null == networkRevision ? _self.networkRevision : networkRevision // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProbeProxyExitParams].
extension ProbeProxyExitParamsPatterns on ProbeProxyExitParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProbeProxyExitParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProbeProxyExitParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProbeProxyExitParams value)  $default,){
final _that = this;
switch (_that) {
case _ProbeProxyExitParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProbeProxyExitParams value)?  $default,){
final _that = this;
switch (_that) {
case _ProbeProxyExitParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  int networkRevision,  String requestId,  String groupId,  String memberId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProbeProxyExitParams() when $default != null:
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.groupId,_that.memberId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  int networkRevision,  String requestId,  String groupId,  String memberId)  $default,) {final _that = this;
switch (_that) {
case _ProbeProxyExitParams():
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.groupId,_that.memberId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  int networkRevision,  String requestId,  String groupId,  String memberId)?  $default,) {final _that = this;
switch (_that) {
case _ProbeProxyExitParams() when $default != null:
return $default(_that.generation,_that.networkRevision,_that.requestId,_that.groupId,_that.memberId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProbeProxyExitParams implements ProbeProxyExitParams {
  const _ProbeProxyExitParams({required this.generation, this.networkRevision = 0, this.requestId = '', required this.groupId, required this.memberId});
  factory _ProbeProxyExitParams.fromJson(Map<String, dynamic> json) => _$ProbeProxyExitParamsFromJson(json);

@override final  int generation;
@override@JsonKey() final  int networkRevision;
@override@JsonKey() final  String requestId;
@override final  String groupId;
@override final  String memberId;

/// Create a copy of ProbeProxyExitParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProbeProxyExitParamsCopyWith<_ProbeProxyExitParams> get copyWith => __$ProbeProxyExitParamsCopyWithImpl<_ProbeProxyExitParams>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProbeProxyExitParamsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProbeProxyExitParams&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.networkRevision, networkRevision) || other.networkRevision == networkRevision)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.memberId, memberId) || other.memberId == memberId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,networkRevision,requestId,groupId,memberId);

@override
String toString() {
  return 'ProbeProxyExitParams(generation: $generation, networkRevision: $networkRevision, requestId: $requestId, groupId: $groupId, memberId: $memberId)';
}


}

/// @nodoc
abstract mixin class _$ProbeProxyExitParamsCopyWith<$Res> implements $ProbeProxyExitParamsCopyWith<$Res> {
  factory _$ProbeProxyExitParamsCopyWith(_ProbeProxyExitParams value, $Res Function(_ProbeProxyExitParams) _then) = __$ProbeProxyExitParamsCopyWithImpl;
@override @useResult
$Res call({
 int generation, int networkRevision, String requestId, String groupId, String memberId
});




}
/// @nodoc
class __$ProbeProxyExitParamsCopyWithImpl<$Res>
    implements _$ProbeProxyExitParamsCopyWith<$Res> {
  __$ProbeProxyExitParamsCopyWithImpl(this._self, this._then);

  final _ProbeProxyExitParams _self;
  final $Res Function(_ProbeProxyExitParams) _then;

/// Create a copy of ProbeProxyExitParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? networkRevision = null,Object? requestId = null,Object? groupId = null,Object? memberId = null,}) {
  return _then(_ProbeProxyExitParams(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,networkRevision: null == networkRevision ? _self.networkRevision : networkRevision // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ProxyExitGeo {

 int get generation; String get requestId; bool get stale; String get leafId; List<String> get pathIds; bool get routeSample; bool get cached; String get ip; String get countryCode; String get asn; String get aso; GeoDatabaseGeneration get dbGeneration;
/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProxyExitGeoCopyWith<ProxyExitGeo> get copyWith => _$ProxyExitGeoCopyWithImpl<ProxyExitGeo>(this as ProxyExitGeo, _$identity);

  /// Serializes this ProxyExitGeo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProxyExitGeo&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.leafId, leafId) || other.leafId == leafId)&&const DeepCollectionEquality().equals(other.pathIds, pathIds)&&(identical(other.routeSample, routeSample) || other.routeSample == routeSample)&&(identical(other.cached, cached) || other.cached == cached)&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.asn, asn) || other.asn == asn)&&(identical(other.aso, aso) || other.aso == aso)&&(identical(other.dbGeneration, dbGeneration) || other.dbGeneration == dbGeneration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,requestId,stale,leafId,const DeepCollectionEquality().hash(pathIds),routeSample,cached,ip,countryCode,asn,aso,dbGeneration);

@override
String toString() {
  return 'ProxyExitGeo(generation: $generation, requestId: $requestId, stale: $stale, leafId: $leafId, pathIds: $pathIds, routeSample: $routeSample, cached: $cached, ip: $ip, countryCode: $countryCode, asn: $asn, aso: $aso, dbGeneration: $dbGeneration)';
}


}

/// @nodoc
abstract mixin class $ProxyExitGeoCopyWith<$Res>  {
  factory $ProxyExitGeoCopyWith(ProxyExitGeo value, $Res Function(ProxyExitGeo) _then) = _$ProxyExitGeoCopyWithImpl;
@useResult
$Res call({
 int generation, String requestId, bool stale, String leafId, List<String> pathIds, bool routeSample, bool cached, String ip, String countryCode, String asn, String aso, GeoDatabaseGeneration dbGeneration
});


$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration;

}
/// @nodoc
class _$ProxyExitGeoCopyWithImpl<$Res>
    implements $ProxyExitGeoCopyWith<$Res> {
  _$ProxyExitGeoCopyWithImpl(this._self, this._then);

  final ProxyExitGeo _self;
  final $Res Function(ProxyExitGeo) _then;

/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? requestId = null,Object? stale = null,Object? leafId = null,Object? pathIds = null,Object? routeSample = null,Object? cached = null,Object? ip = null,Object? countryCode = null,Object? asn = null,Object? aso = null,Object? dbGeneration = null,}) {
  return _then(_self.copyWith(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,leafId: null == leafId ? _self.leafId : leafId // ignore: cast_nullable_to_non_nullable
as String,pathIds: null == pathIds ? _self.pathIds : pathIds // ignore: cast_nullable_to_non_nullable
as List<String>,routeSample: null == routeSample ? _self.routeSample : routeSample // ignore: cast_nullable_to_non_nullable
as bool,cached: null == cached ? _self.cached : cached // ignore: cast_nullable_to_non_nullable
as bool,ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as String,aso: null == aso ? _self.aso : aso // ignore: cast_nullable_to_non_nullable
as String,dbGeneration: null == dbGeneration ? _self.dbGeneration : dbGeneration // ignore: cast_nullable_to_non_nullable
as GeoDatabaseGeneration,
  ));
}
/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration {

  return $GeoDatabaseGenerationCopyWith<$Res>(_self.dbGeneration, (value) {
    return _then(_self.copyWith(dbGeneration: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProxyExitGeo].
extension ProxyExitGeoPatterns on ProxyExitGeo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProxyExitGeo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProxyExitGeo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProxyExitGeo value)  $default,){
final _that = this;
switch (_that) {
case _ProxyExitGeo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProxyExitGeo value)?  $default,){
final _that = this;
switch (_that) {
case _ProxyExitGeo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  String requestId,  bool stale,  String leafId,  List<String> pathIds,  bool routeSample,  bool cached,  String ip,  String countryCode,  String asn,  String aso,  GeoDatabaseGeneration dbGeneration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProxyExitGeo() when $default != null:
return $default(_that.generation,_that.requestId,_that.stale,_that.leafId,_that.pathIds,_that.routeSample,_that.cached,_that.ip,_that.countryCode,_that.asn,_that.aso,_that.dbGeneration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  String requestId,  bool stale,  String leafId,  List<String> pathIds,  bool routeSample,  bool cached,  String ip,  String countryCode,  String asn,  String aso,  GeoDatabaseGeneration dbGeneration)  $default,) {final _that = this;
switch (_that) {
case _ProxyExitGeo():
return $default(_that.generation,_that.requestId,_that.stale,_that.leafId,_that.pathIds,_that.routeSample,_that.cached,_that.ip,_that.countryCode,_that.asn,_that.aso,_that.dbGeneration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  String requestId,  bool stale,  String leafId,  List<String> pathIds,  bool routeSample,  bool cached,  String ip,  String countryCode,  String asn,  String aso,  GeoDatabaseGeneration dbGeneration)?  $default,) {final _that = this;
switch (_that) {
case _ProxyExitGeo() when $default != null:
return $default(_that.generation,_that.requestId,_that.stale,_that.leafId,_that.pathIds,_that.routeSample,_that.cached,_that.ip,_that.countryCode,_that.asn,_that.aso,_that.dbGeneration);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProxyExitGeo implements ProxyExitGeo {
  const _ProxyExitGeo({required this.generation, this.requestId = '', this.stale = false, this.leafId = '', final  List<String> pathIds = const [], this.routeSample = false, this.cached = false, this.ip = '', this.countryCode = '', this.asn = '', this.aso = '', this.dbGeneration = const GeoDatabaseGeneration()}): _pathIds = pathIds;
  factory _ProxyExitGeo.fromJson(Map<String, dynamic> json) => _$ProxyExitGeoFromJson(json);

@override final  int generation;
@override@JsonKey() final  String requestId;
@override@JsonKey() final  bool stale;
@override@JsonKey() final  String leafId;
 final  List<String> _pathIds;
@override@JsonKey() List<String> get pathIds {
  if (_pathIds is EqualUnmodifiableListView) return _pathIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pathIds);
}

@override@JsonKey() final  bool routeSample;
@override@JsonKey() final  bool cached;
@override@JsonKey() final  String ip;
@override@JsonKey() final  String countryCode;
@override@JsonKey() final  String asn;
@override@JsonKey() final  String aso;
@override@JsonKey() final  GeoDatabaseGeneration dbGeneration;

/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProxyExitGeoCopyWith<_ProxyExitGeo> get copyWith => __$ProxyExitGeoCopyWithImpl<_ProxyExitGeo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProxyExitGeoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProxyExitGeo&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.leafId, leafId) || other.leafId == leafId)&&const DeepCollectionEquality().equals(other._pathIds, _pathIds)&&(identical(other.routeSample, routeSample) || other.routeSample == routeSample)&&(identical(other.cached, cached) || other.cached == cached)&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.asn, asn) || other.asn == asn)&&(identical(other.aso, aso) || other.aso == aso)&&(identical(other.dbGeneration, dbGeneration) || other.dbGeneration == dbGeneration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,generation,requestId,stale,leafId,const DeepCollectionEquality().hash(_pathIds),routeSample,cached,ip,countryCode,asn,aso,dbGeneration);

@override
String toString() {
  return 'ProxyExitGeo(generation: $generation, requestId: $requestId, stale: $stale, leafId: $leafId, pathIds: $pathIds, routeSample: $routeSample, cached: $cached, ip: $ip, countryCode: $countryCode, asn: $asn, aso: $aso, dbGeneration: $dbGeneration)';
}


}

/// @nodoc
abstract mixin class _$ProxyExitGeoCopyWith<$Res> implements $ProxyExitGeoCopyWith<$Res> {
  factory _$ProxyExitGeoCopyWith(_ProxyExitGeo value, $Res Function(_ProxyExitGeo) _then) = __$ProxyExitGeoCopyWithImpl;
@override @useResult
$Res call({
 int generation, String requestId, bool stale, String leafId, List<String> pathIds, bool routeSample, bool cached, String ip, String countryCode, String asn, String aso, GeoDatabaseGeneration dbGeneration
});


@override $GeoDatabaseGenerationCopyWith<$Res> get dbGeneration;

}
/// @nodoc
class __$ProxyExitGeoCopyWithImpl<$Res>
    implements _$ProxyExitGeoCopyWith<$Res> {
  __$ProxyExitGeoCopyWithImpl(this._self, this._then);

  final _ProxyExitGeo _self;
  final $Res Function(_ProxyExitGeo) _then;

/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? requestId = null,Object? stale = null,Object? leafId = null,Object? pathIds = null,Object? routeSample = null,Object? cached = null,Object? ip = null,Object? countryCode = null,Object? asn = null,Object? aso = null,Object? dbGeneration = null,}) {
  return _then(_ProxyExitGeo(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,leafId: null == leafId ? _self.leafId : leafId // ignore: cast_nullable_to_non_nullable
as String,pathIds: null == pathIds ? _self._pathIds : pathIds // ignore: cast_nullable_to_non_nullable
as List<String>,routeSample: null == routeSample ? _self.routeSample : routeSample // ignore: cast_nullable_to_non_nullable
as bool,cached: null == cached ? _self.cached : cached // ignore: cast_nullable_to_non_nullable
as bool,ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,asn: null == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as String,aso: null == aso ? _self.aso : aso // ignore: cast_nullable_to_non_nullable
as String,dbGeneration: null == dbGeneration ? _self.dbGeneration : dbGeneration // ignore: cast_nullable_to_non_nullable
as GeoDatabaseGeneration,
  ));
}

/// Create a copy of ProxyExitGeo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GeoDatabaseGenerationCopyWith<$Res> get dbGeneration {

  return $GeoDatabaseGenerationCopyWith<$Res>(_self.dbGeneration, (value) {
    return _then(_self.copyWith(dbGeneration: value));
  });
}
}


/// @nodoc
mixin _$ActionResult {

 ActionMethod get method; dynamic get data; String? get id; ResultType get code;
/// Create a copy of ActionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionResultCopyWith<ActionResult> get copyWith => _$ActionResultCopyWithImpl<ActionResult>(this as ActionResult, _$identity);

  /// Serializes this ActionResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionResult&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.id, id) || other.id == id)&&(identical(other.code, code) || other.code == code));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,method,const DeepCollectionEquality().hash(data),id,code);

@override
String toString() {
  return 'ActionResult(method: $method, data: $data, id: $id, code: $code)';
}


}

/// @nodoc
abstract mixin class $ActionResultCopyWith<$Res>  {
  factory $ActionResultCopyWith(ActionResult value, $Res Function(ActionResult) _then) = _$ActionResultCopyWithImpl;
@useResult
$Res call({
 ActionMethod method, dynamic data, String? id, ResultType code
});




}
/// @nodoc
class _$ActionResultCopyWithImpl<$Res>
    implements $ActionResultCopyWith<$Res> {
  _$ActionResultCopyWithImpl(this._self, this._then);

  final ActionResult _self;
  final $Res Function(ActionResult) _then;

/// Create a copy of ActionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? method = null,Object? data = freezed,Object? id = freezed,Object? code = null,}) {
  return _then(_self.copyWith(
method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as ActionMethod,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ResultType,
  ));
}

}


/// Adds pattern-matching-related methods to [ActionResult].
extension ActionResultPatterns on ActionResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActionResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActionResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActionResult value)  $default,){
final _that = this;
switch (_that) {
case _ActionResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActionResult value)?  $default,){
final _that = this;
switch (_that) {
case _ActionResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ActionMethod method,  dynamic data,  String? id,  ResultType code)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActionResult() when $default != null:
return $default(_that.method,_that.data,_that.id,_that.code);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ActionMethod method,  dynamic data,  String? id,  ResultType code)  $default,) {final _that = this;
switch (_that) {
case _ActionResult():
return $default(_that.method,_that.data,_that.id,_that.code);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ActionMethod method,  dynamic data,  String? id,  ResultType code)?  $default,) {final _that = this;
switch (_that) {
case _ActionResult() when $default != null:
return $default(_that.method,_that.data,_that.id,_that.code);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ActionResult implements ActionResult {
  const _ActionResult({required this.method, required this.data, this.id, this.code = ResultType.success});
  factory _ActionResult.fromJson(Map<String, dynamic> json) => _$ActionResultFromJson(json);

@override final  ActionMethod method;
@override final  dynamic data;
@override final  String? id;
@override@JsonKey() final  ResultType code;

/// Create a copy of ActionResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionResultCopyWith<_ActionResult> get copyWith => __$ActionResultCopyWithImpl<_ActionResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActionResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionResult&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.id, id) || other.id == id)&&(identical(other.code, code) || other.code == code));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,method,const DeepCollectionEquality().hash(data),id,code);

@override
String toString() {
  return 'ActionResult(method: $method, data: $data, id: $id, code: $code)';
}


}

/// @nodoc
abstract mixin class _$ActionResultCopyWith<$Res> implements $ActionResultCopyWith<$Res> {
  factory _$ActionResultCopyWith(_ActionResult value, $Res Function(_ActionResult) _then) = __$ActionResultCopyWithImpl;
@override @useResult
$Res call({
 ActionMethod method, dynamic data, String? id, ResultType code
});




}
/// @nodoc
class __$ActionResultCopyWithImpl<$Res>
    implements _$ActionResultCopyWith<$Res> {
  __$ActionResultCopyWithImpl(this._self, this._then);

  final _ActionResult _self;
  final $Res Function(_ActionResult) _then;

/// Create a copy of ActionResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? method = null,Object? data = freezed,Object? id = freezed,Object? code = null,}) {
  return _then(_ActionResult(
method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as ActionMethod,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ResultType,
  ));
}


}

// dart format on
