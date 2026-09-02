/// URL del portal web de Éxodo (proyecto exodo-web).
///
/// Producción: pásala con --dart-define=EXODO_WEB_URL=https://... cuando el
/// portal se despliegue. Mientras el portal vive como dev server Vite en el
/// PC, la app abre la IP LAN (el teléfono debe estar en el mismo Wi-Fi;
/// arrancar el server con `npm run dev -- --host`).
const String _prodUrl = String.fromEnvironment('EXODO_WEB_URL');

const String _lanDevUrl = 'http://192.168.8.223:5173';

String get exodoWebUrl => _prodUrl.isNotEmpty ? _prodUrl : _lanDevUrl;
