# 🚇 Túnel HTTPS para desarrollo (Cloudflare Tunnel)

## Por qué

Desde Android 9 (Pie), el sistema operativo **bloquea todo el tráfico HTTP en claro** por defecto. El LG V60 con Android 10+ no puede hablar con tu `localhost:3000` por HTTP. Solo acepta HTTPS.

Solución: exponer tu backend local a internet con una URL HTTPS pública usando **Cloudflare Tunnel** (gratis, sin cuenta, sin tarjeta).

## Setup (una sola vez)

```powershell
winget install --id Cloudflare.cloudflared
```

Si no usas winget, descarga desde: https://github.com/cloudflare/cloudflared/releases

## Uso cada vez que quieras probar la app en el teléfono

**Terminal 1** — backend:
```powershell
cd "D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend"
npm run dev
```

**Terminal 2** — túnel HTTPS:
```powershell
cd "D:\Proyecto Behavior AI Exodo\exodo-app\exodo-backend"
.\start-dev-tunnel.ps1
```

Verás una salida tipo:
```
+-----------------------------------------------------------+
|  Your quick tunnel has been created! Visit it at:          |
|  https://random-word-1234.trycloudflare.com               |
+-----------------------------------------------------------+
```

**Terminal 3** — Flutter con la URL pública:
```powershell
cd "D:\Proyecto Behavior AI Exodo\exodo-app\exodo"
flutter run -d LMV600TMe5979248 --no-pub --dart-define=BACKEND_URL=https://random-word-1234.trycloudflare.com
```

Cambia `random-word-1234` por la URL real que te dio cloudflared. Cada vez que cierres el túnel y lo abras, la URL cambia (es gratis pero aleatoria).

## Producción (siguiente paso)

Para cuando Éxodo se lance al público, el backend debe estar en un servidor permanente con HTTPS estable. Opciones:

| Plataforma | Plan gratis | HTTPS | Tiempo de setup |
|---|---|---|---|
| Railway | $5 crédito/mes | sí | 5 min |
| Render | 750 h/mes | sí | 10 min |
| Fly.io | generoso | sí | 15 min |

El backend ya tiene `railway.toml` configurado, así que Railway es la opción más rápida. Solo hay que conectar el repo de GitHub y listo.

## Por qué NO usar `http://192.168.x.x:3000` directo

Aunque pongas la IP correcta de tu PC:
- ❌ Solo funciona cuando el celular está en tu misma Wi-Fi.
- ❌ Android 9+ lo bloquea por cleartext HTTP.
- ❌ Si cambias de Wi-Fi o reinicias el router, la IP cambia.
- ❌ Cuando un usuario real descargue Éxodo desde Play Store, no va a tener acceso a tu Wi-Fi privada.

Por eso **siempre HTTPS público**, incluso en desarrollo. Es la única forma de que la app funcione igual de local a producción.