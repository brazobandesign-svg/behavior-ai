// Enlace oficial de la app móvil de Exodo en Google Play
// (compartido por DrawerMenu y SidebarRail)
export const EXODO_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.behavior.exodo';

export const openExodoApp = () => {
  try {
    window.open(EXODO_PLAY_STORE_URL, '_blank');
  } catch (_) {}
};
