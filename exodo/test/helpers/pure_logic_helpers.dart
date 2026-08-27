/// Helpers de lógica pura extraídos para testeo unitario.
///
/// IMPORTANTE: estos helpers replican EXACTAMENTE la lógica de producción
/// (mismas reglas, mismo formato). No cambian el comportamiento de la app;
/// son la superficie testeable de:
/// - `AppState._makeUniqueTitle` (app_state.dart)
/// - `ExpedientesRepository._prefsKey` (expedientes_repository.dart)
/// - `ChatService._candidateUrls` + gate kDebugMode (chat_service.dart)
library;

/// Deduplicación de títulos: si `base` ya existe en [existingTitles],
/// agrega sufijo " ·2", " ·3"... hasta encontrar uno libre.
/// Réplica exacta de AppState._makeUniqueTitle.
String makeUniqueTitle(String base, Set<String> existingTitles) {
  final clean = base.trim();
  if (clean.isEmpty) return clean;
  final existing = existingTitles.map((t) => t.trim()).toSet();
  if (!existing.contains(clean)) return clean;
  var n = 2;
  while (existing.contains('$clean ·$n')) {
    n++;
  }
  return '$clean ·$n';
}

/// Llave de caché local de expedientes, con scope por uid.
/// Réplica exacta de ExpedientesRepository._prefsKey:
/// 'exodo_local_expedientes_`<uid>`' o 'exodo_local_expedientes_anon'.
String expedientesPrefsKey({String? uid}) {
  final scope = (uid == null || uid.isEmpty) ? 'anon' : uid;
  return 'exodo_local_expedientes_$scope';
}

/// Candidatos de URL del backend filtrados por modo release.
///
/// En release (kDebugMode == false) los endpoints HTTP locales
/// (127.0.0.1 / 192.168.*) NUNCA se incluyen: el JWT viaja solo por HTTPS.
///
/// [isDebug] simula kDebugMode para poder testear ambos modos.
List<String> candidateUrls({
  required bool isDebug,
  List<String> envUrls = const [],
  String? workingUrl,
}) {
  if (workingUrl != null) return [workingUrl];
  final list = <String>[];
  for (final env in envUrls) {
    if (env.isNotEmpty) {
      final url = env.endsWith('/api/chat') ? env : '$env/api/chat';
      if (!list.contains(url)) list.add(url);
    }
  }

  const prodUrl = 'https://behavior-ai-production.up.railway.app/api/chat';

  // SEGURIDAD (auditoría C3): candidatos HTTP locales SOLO en debug.
  if (isDebug) {
    list.add('http://127.0.0.1:3000/api/chat');
    list.add('http://192.168.8.223:3000/api/chat');
  }
  if (!list.contains(prodUrl)) list.add(prodUrl);
  return list;
}

// ─── [Punto 4] Compuertas silenciosas de pago (billing) ──────────────────────
// Réplicas exactas de la política implementada en producción:
// - StripeService.startCheckoutSession (guard interno JWT + conectividad)
// - UpgradeModal botón "Adquirir Pro" (invitado u offline → no-op con háptica)
// - Drawer botón de portal (sólo cuentas Pro; offline → no-op silencioso)

/// ¿Puede ejecutarse un checkout de Stripe? Réplica exacta del guard interno
/// de `StripeService.startCheckoutSession`: requiere JWT presente y no vacío
/// Y conectividad activa. Cualquier otra cosa → retorno silencioso `false`.
bool canStartCheckout({String? jwt, required bool isOnline}) =>
    !(jwt == null || jwt.isEmpty || !isOnline);

/// ¿El botón "Adquirir Pro" es un no-op silencioso? Réplica exacta del guard
/// de `UpgradeModal`: invitado u offline → sí (retorno temprano + háptica).
bool purchaseButtonIsNoOp({required bool isGuestUser, required bool isOnline}) =>
    isGuestUser || !isOnline;

/// ¿El botón del portal de gestión (drawer, cuentas Pro) es no-op? Réplica
/// del guard añadido en `DrawerMenu._showBillingModal`: offline → sí.
bool portalButtonIsNoOp({required bool isOnline}) => !isOnline;
