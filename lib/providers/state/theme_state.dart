part of '../state.dart';

@riverpod
VM3<bool, int, bool> checkIp(Ref ref) {
  final isInit = ref.watch(initProvider);
  final checkIpNum = ref.watch(checkIpNumProvider);
  final containsDetection = ref.watch(
    dashboardStateProvider.select(
      (state) =>
          state.dashboardWidgets.contains(DashboardWidget.networkDetection),
    ),
  );
  return VM3(isInit, checkIpNum, containsDetection);
}

@riverpod
ColorScheme genColorScheme(
  Ref ref,
  Brightness brightness, {
  Color? color,
  bool ignoreConfig = false,
}) {
  final vm2 = ref.watch(
    themeSettingProvider.select(
      (state) => VM2(state.primaryColor, state.schemeVariant),
    ),
  );
  final Color brand;
  final variant = vm2.b;
  final ColorScheme seeded;
  if (color == null && (ignoreConfig == true || vm2.a == null)) {
    brand =
        globalState.corePalette
            ?.toColorScheme(brightness: brightness)
            .primary ??
        globalState.accentColor;
    seeded = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      dynamicSchemeVariant: variant,
    );
  } else {
    brand = color ?? Color(vm2.a!);
    seeded = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      dynamicSchemeVariant: variant,
    );
  }
  // Lock brand hue — fromSeed often turns orange into mustard/brown.
  return seeded.toNeutralSurfaces(brand: brand);
}

@riverpod
Brightness currentBrightness(Ref ref) {
  final themeMode = ref.watch(
    themeSettingProvider.select((state) => state.themeMode),
  );
  final systemBrightness = ref.watch(systemBrightnessProvider);
  return switch (themeMode) {
    ThemeMode.system => systemBrightness,
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
  };
}


