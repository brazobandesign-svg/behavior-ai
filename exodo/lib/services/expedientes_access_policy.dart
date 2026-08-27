/// [Punto 3] Política de acceso Guest al módulo Expedientes (Artefactos).
///
/// Fuente única de verdad compartida por:
/// - `DrawerMenu` (ítem oculto para invitados)
/// - `ExpedientesScreen` (guard de apertura sin tocar el repositorio)
/// - `ArtifactCard` / `ArtifactFullscreen` (acción de guardado no dibujada)
/// - `ExpedientesRepository.createExpediente` (hard-guard de persistencia)
///
/// Regla de negocio: un invitado puede VER e interactuar con artefactos en
/// el chat/sandbox, pero NUNCA guardarlos en su archivo permanente.
///
/// Este archivo es Dart puro (sin Flutter ni plugins) a propósito: así los
/// unit tests importan la MISMA lógica que ejecuta producción, sin réplicas.
library;

/// True si la identidad de cuenta de Supabase corresponde a un invitado:
/// sin usuario activo, sesión anónima o email ausente/vacío/espacios.
///
/// Espejo exacto de `AppState.isGuestUser` a nivel de sesión de Supabase
/// (AppState añade además el flag local `_hasCachedSession`, que no aplica
/// dentro del repositorio porque ahí "sin usuario" también es invitado).
bool isGuestIdentity({
  String? userId,
  required bool isAnonymous,
  String? email,
}) {
  if (userId == null || userId.trim().isEmpty) return true;
  if (isAnonymous) return true;
  if (email == null) return true;
  return email.trim().isEmpty;
}

/// El ítem/módulo de Expedientes solo es visible para cuentas autenticadas.
bool expedientesModuleVisible({required bool isGuestUser}) => !isGuestUser;

/// Guardar artefactos como expedientes queda reservado a cuentas reales.
bool canSaveExpediente({required bool isGuestUser}) => !isGuestUser;
