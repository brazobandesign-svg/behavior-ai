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
///
/// **v1.2 — fix del cambio de idioma que no se propagaba a widgets `const`
/// ni a subárboles que no leían el InheritedWidget en cada build.**
/// Ahora el estado es un `ChangeNotifier` (no un VO con VoidCallback) y se
/// expone a través de un `AppI18nProviderScope` además del legacy
/// `_I18nScope`. Cualquier `context.watch<AppI18nProvider>()` también
/// dispara rebuild, y `MaterialApp` recibe un `key: ValueKey(userLocale)`
/// para forzar rebuild completo cuando cambia el locale.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_translations.dart';

class AppI18n {
  final String localeCode;
  AppI18n(this.localeCode);

  static AppI18n of(BuildContext context) {
    // [v1.2] Doble vía: scope moderno (ChangeNotifier) primero, luego
    // legacy InheritedWidget. Cualquiera de los dos es fuente de verdad.
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppI18nProviderScope>();
    if (scope != null) {
      return AppI18n(scope.state.currentLocale ?? _systemLocale());
    }
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

/// [v1.2] Estado interno ahora es un ChangeNotifier. Mantiene `onChange`
/// por compatibilidad con código legacy que aún se suscriba así.
/// Sigue siendo PRIVADO (prefijo `_`) para mantener la encapsulación del
/// archivo y respetar la regla 3 del leeme (aislamiento por archivos).
class _AppI18nState extends ChangeNotifier {
  String? currentLocale;
  VoidCallback? onChange;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    currentLocale = prefs.getString('exodo_locale');
    AppI18n.setInstance(currentLocale);
    notifyListeners();
    onChange?.call();
  }

  Future<void> setLocale(String? code) async {
    currentLocale = code;
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove('exodo_locale');
    } else {
      await prefs.setString('exodo_locale', code);
    }
    AppI18n.setInstance(code);
    // [v1.2] Doble canal para garantizar rebuild:
    //  • notifyListeners → cubre `context.watch<AppI18nProvider>()`.
    //  • onChange → cubre el legacy InheritedWidget.
    notifyListeners();
    onChange?.call();
  }
}

class _I18nScope extends InheritedWidget {
  final _AppI18nState state;
  const _I18nScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_I18nScope old) =>
      old.state.currentLocale != state.currentLocale;
}

/// [v1.2] Scope widget adicional que expone el mismo ChangeNotifier a
/// través de `findAncestorWidgetOfExactType`. Es invisible y gratuito.
class AppI18nProviderScope extends InheritedWidget {
  final _AppI18nState state;
  const AppI18nProviderScope(
      {required this.state, required super.child, super.key});

  @override
  bool updateShouldNotify(AppI18nProviderScope old) =>
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
    // [v1.2] Suscribirse a sí mismo para que cualquier
    // `context.watch<AppI18nProvider>()` también dispare rebuild.
    state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _I18nScope(
      state: state,
      child: AppI18nProviderScope(state: state, child: widget.child),
    );
  }
}

/// Acceso al estado para setear locale desde cualquier sitio (e.g. drawer).
extension AppI18nContext on BuildContext {
  Future<void> setLocale(String? code) async {
    // [v1.2] Buscar primero el scope moderno, luego caer al legacy.
    final scope = findAncestorWidgetOfExactType<AppI18nProviderScope>();
    if (scope != null) {
      await scope.state.setLocale(code);
      return;
    }
    final inherited = findAncestorWidgetOfExactType<_I18nScope>();
    await inherited?.state.setLocale(code);
  }

  String? get currentLocaleCode {
    final scope = dependOnInheritedWidgetOfExactType<AppI18nProviderScope>();
    if (scope != null) return scope.state.currentLocale;
    final inherited = dependOnInheritedWidgetOfExactType<_I18nScope>();
    return inherited?.state.currentLocale;
  }
}
