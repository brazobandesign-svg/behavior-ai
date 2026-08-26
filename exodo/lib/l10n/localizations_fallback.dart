/// Delegates de localización de Éxodo con fallback para locales que el SDK
/// de Flutter (`flutter_localizations`) no soporta.
///
/// CAUSA RAÍZ del crash P1 "pantalla gris" (2026-08-26): al seleccionar
/// Kreyòl (`ht`), `MaterialApp.locale = Locale('ht')` no puede ser resuelto
/// por `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations`
/// (el SDK no incluye el criollo haitiano). El primer widget que invoca
/// `MaterialLocalizations.of(context)` lanza "No MaterialLocalizations found."
/// en fase de build y `ErrorWidget.builder` pinta la pantalla gris completa.
/// El fallo se correlacionó con "offline" (público haitiano sin datos), pero
/// es independiente de la red.
///
/// Solución: envolver a los delegates oficiales; los locales sin soporte del
/// SDK reciben los formatos de `fr` (el criollo haitiano es de léxico
/// francés y los textos de la app ya salen de `app_translations.dart`).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Delegado Material: sirve cualquier locale; los no soportados por el SDK
/// (p. ej. `ht`) reciben los formatos base de `fr`.
class ExodoMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const ExodoMaterialLocalizationsDelegate();

  static const Locale _sdkFallback = Locale('fr');

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final effective = GlobalMaterialLocalizations.delegate.isSupported(locale)
        ? locale
        : _sdkFallback;
    return GlobalMaterialLocalizations.delegate.load(effective);
  }

  @override
  bool shouldReload(ExodoMaterialLocalizationsDelegate old) => false;
}

/// Delegado Cupertino: mismo fallback que el delegado Material.
class ExodoCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const ExodoCupertinoLocalizationsDelegate();

  static const Locale _sdkFallback = Locale('fr');

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final effective = GlobalCupertinoLocalizations.delegate.isSupported(locale)
        ? locale
        : _sdkFallback;
    return GlobalCupertinoLocalizations.delegate.load(effective);
  }

  @override
  bool shouldReload(ExodoCupertinoLocalizationsDelegate old) => false;
}

/// Delegates oficiales de Éxodo para `MaterialApp.localizationsDelegates`.
const List<LocalizationsDelegate<dynamic>> kExodoLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  ExodoMaterialLocalizationsDelegate(),
  GlobalWidgetsLocalizations.delegate,
  ExodoCupertinoLocalizationsDelegate(),
];
