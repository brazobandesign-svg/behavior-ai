/// Helper de traducción reactivo.
///
/// Uso:
///   final i18n = AppI18n.of(context);
///   Text(i18n.t('chat.placeholder'));
///
/// El locale se persiste en SharedPreferences (`exodo_locale`) y se
/// sincroniza con el `MaterialApp.locale` mediante `AppState.currentLocale`.
///
/// Si `currentLocale == null` → usa el locale del sistema (fallback).
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_translations.dart';

class AppI18n {
  final String localeCode;
  AppI18n(this.localeCode);

  static AppI18n of(BuildContext context) {
    final state = _maybeFindState(context);
    return AppI18n(state?.currentLocale ?? _systemLocale());
  }

  /// Acceso de bajo nivel (sin BuildContext) — útil en singletons.
  static AppI18n get instance => AppI18n(_instanceCode ?? _systemLocale());
  static String? _instanceCode;

  static String _systemLocale() {
    try {
      final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      if (kAppLocales.any((l) => l.code == code)) return code;
    } catch (_) {}
    return 'es';
  }

  String t(String key) {
    final map = translationsFor(localeCode);
    return map[key] ?? translationsFor('es')[key] ?? key;
  }

  /// Atajo: `i18n.l('es')` → 'Español 🇪🇸'
  String l(String code) {
    final loc = kAppLocales.firstWhere((l) => l.code == code,
        orElse: () => kAppLocales.first);
    return '${loc.nativeName} ${loc.flag}';
  }

  // Estado interno (expuesto solo para AppState).
  static _AppI18nState? _maybeFindState(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<_I18nScope>();
    return inherited?.state;
  }

  static void setInstance(String? code) => _instanceCode = code;
}

class _AppI18nState {
  String? currentLocale;
  VoidCallback? onChange;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    currentLocale = prefs.getString('exodo_locale');
    AppI18n.setInstance(currentLocale);
  }

  Future<void> setLocale(String? code) async {
    currentLocale = code;
    AppI18n.setInstance(code);
    onChange?.call();
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove('exodo_locale');
    } else {
      await prefs.setString('exodo_locale', code);
    }
  }
}

class _I18nScope extends InheritedWidget {
  final _AppI18nState state;
  const _I18nScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_I18nScope old) =>
      old.state.currentLocale != state.currentLocale;
}

/// Provider que vive encima del MaterialApp. Lo crea `ExodoApp` y lo lee
/// cualquier widget con `AppI18n.of(context)`.
class AppI18nProvider extends StatefulWidget {
  final Widget child;
  const AppI18nProvider({super.key, required this.child});

  @override
  State<AppI18nProvider> createState() => _AppI18nProviderState();
}

class _AppI18nProviderState extends State<AppI18nProvider> {
  final _AppI18nState state = _AppI18nState()..currentLocale = null;

  @override
  void initState() {
    super.initState();
    state.load();
    state.onChange = () {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return _I18nScope(state: state, child: widget.child);
  }
}

/// Acceso al estado para setear locale desde cualquier sitio (e.g. drawer).
extension AppI18nContext on BuildContext {
  Future<void> setLocale(String? code) async {
    final inherited = dependOnInheritedWidgetOfExactType<_I18nScope>();
    await inherited?.state.setLocale(code);
  }

  String? get currentLocaleCode {
    final inherited = dependOnInheritedWidgetOfExactType<_I18nScope>();
    return inherited?.state.currentLocale;
  }
}
