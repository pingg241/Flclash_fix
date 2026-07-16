import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/pages.dart';

Future<void> initializeApplicationAfterFrame({
  required Future<void> Function() attach,
  required Future<void> Function() initializeLinks,
  required Future<void> Function() initializeShortcuts,
}) async {
  await attach();
  await initializeLinks();
  await initializeShortcuts();
}

class ConnectivityUpdateCoordinator {
  int _generation = 0;
  bool _hasVpn = false;

  @visibleForTesting
  bool get hasVpn => _hasVpn;

  Future<void> update({
    required List<ConnectivityResult> results,
    required Future<bool> Function(bool Function() isCurrent) refreshLocalIp,
    required void Function() checkIp,
    bool Function()? isActive,
  }) async {
    final generation = ++_generation;
    bool isCurrent() =>
        generation == _generation && (isActive == null || isActive());
    try {
      if (!await refreshLocalIp(isCurrent) || !isCurrent()) {
        return;
      }
    } catch (_) {
      if (!isCurrent()) {
        return;
      }
      rethrow;
    }
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_hasVpn == hasVpn) {
      checkIp();
    }
    _hasVpn = hasVpn;
  }

  void invalidate() {
    _generation++;
  }
}

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  late final AsyncPeriodicTask _autoUpdateProfilesTask;
  final _connectivityUpdates = ConnectivityUpdateCoordinator();

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: commonSharedXPageTransitions,
      TargetPlatform.windows: commonSharedXPageTransitions,
      TargetPlatform.linux: commonSharedXPageTransitions,
      TargetPlatform.macOS: commonSharedXPageTransitions,
    },
  );

  ColorScheme _getAppColorScheme({
    required Brightness brightness,
    int? primaryColor,
  }) {
    return ref.read(genColorSchemeProvider(brightness));
  }

  @override
  void initState() {
    super.initState();
    _autoUpdateProfilesTask = AsyncPeriodicTask(
      interval: const Duration(minutes: 20),
      task: () =>
          ref.read(profilesActionProvider.notifier).autoUpdateProfiles(),
      onError: (error, stackTrace) {
        commonPrint.log(
          'Auto-update profiles failed: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        runAsyncSafely(
          operation: _initializeAfterFrame,
          onError: (error, stackTrace) {
            commonPrint.log(
              'Application initialization failed: $error\n$stackTrace',
              logLevel: LogLevel.error,
            );
            globalState.showNotifier(error.toString());
          },
        ),
      );
    });
  }

  Future<void> _initializeAfterFrame() async {
    if (globalState.navigatorKey.currentContext == null) {
      exit(0);
    }
    await initializeApplicationAfterFrame(
      attach: globalState.attach,
      initializeLinks: () async {
        if (!mounted) return;
        _autoUpdateProfilesTask.start();
        await _initLink();
      },
      initializeShortcuts: () async {
        if (!mounted) return;
        final currentApp = app;
        if (currentApp == null) return;
        if (await currentApp.initShortcuts() != true) {
          throw StateError('Failed to initialize application shortcuts');
        }
      },
    );
  }

  Future<void> _initLink() async {
    await linkManager.initAppLinksListen((url) async {
      if (!mounted) {
        return;
      }
      final res = await globalState.showMessage(
        title: currentAppLocalizations.addProfile,
        message: TextSpan(
          children: [
            TextSpan(text: currentAppLocalizations.doYouWantToPass),
            TextSpan(
              text: ' $url ',
              style: TextStyle(
                color: context.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: context.colorScheme.primary,
              ),
            ),
            TextSpan(text: currentAppLocalizations.createProfile),
          ],
        ),
      );
      if (res != true || !mounted) return;
      await ref.read(profilesActionProvider.notifier).addProfileFormURL(url);
    });
  }

  Widget _buildPlatformState({required Widget child}) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(child: ProxyManager(child: child)),
        ),
      );
    }
    return AndroidManager(child: TileManager(child: child));
  }

  Widget _buildState({required Widget child}) {
    return AppStateManager(
      child: CoreManager(
        child: ConnectivityManager(
          onConnectivityChanged: (results) async {
            commonPrint.log('connectivityChanged ${results.toString()}');
            ref.read(networkRevisionProvider.notifier).bump();
            await _connectivityUpdates.update(
              results: results,
              refreshLocalIp: (isCurrent) => ref
                  .read(systemActionProvider.notifier)
                  .updateLocalIp(isCurrent: isCurrent),
              checkIp: () => ref.read(checkIpNumProvider.notifier).add(),
              isActive: () => mounted,
            );
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildPlatformApp({required Widget child}) {
    if (system.isDesktop) {
      return WindowHeaderContainer(child: child);
    }
    return VpnManager(child: child);
  }

  Widget _buildApp({required Widget child}) {
    return StatusManager(child: ThemeManager(child: child));
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (_, child) {
            return AppEnvManager(
              child: _buildApp(
                child: _buildPlatformState(
                  child: _buildState(child: _buildPlatformApp(child: child!)),
                ),
              ),
            );
          },
          scrollBehavior: BaseScrollBehavior(),
          title: appName,
          locale: utils.getLocaleForString(locale),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.light,
              primaryColor: themeProps.primaryColor,
            ),
            scaffoldBackgroundColor: Colors.white,
            canvasColor: Colors.white,
            dividerColor: const Color(0xFFE8E6E3),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            navigationBarTheme: const NavigationBarThemeData(
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              height: 72,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              elevation: 0,
              highlightElevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              backgroundColor: BrandSoft.fill,
              foregroundColor: BrandSoft.onFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF1C1917),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.dark,
              primaryColor: themeProps.primaryColor,
            ).toPureBlack(themeProps.pureBlack),
            cardTheme: CardThemeData(
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          home: child!,
        );
      },
      child: const HomePage(),
    );
  }

  @override
  void dispose() {
    _connectivityUpdates.invalidate();
    _autoUpdateProfilesTask.stop();
    unawaited(
      linkManager.destroy().catchError((Object error, StackTrace stackTrace) {
        commonPrint.log(
          'Failed to stop app link listener: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }),
    );
    final systemAction = ref.read(systemActionProvider.notifier);
    unawaited(
      systemAction.handleExit().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        commonPrint.log(
          'Application shutdown failed: $error\n$stackTrace',
          logLevel: LogLevel.warning,
        );
      }),
    );
    super.dispose();
  }
}
