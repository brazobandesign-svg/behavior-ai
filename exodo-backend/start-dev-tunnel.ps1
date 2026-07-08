# ============================================================
# start-dev-tunnel.ps1
# Expone tu backend local (localhost:3000) a internet vía HTTPS
# usando Cloudflare Tunnel (gratis, sin cuenta).
#
# Por qué: la app Éxodo (en Android 9+) SOLO acepta HTTPS para
# conectarse a un backend. Hablar HTTP a tu IP LAN está bloqueado
# por el sistema operativo. Con este túnel, tu localhost:3000
# queda accesible como https://xxx.trycloudflare.com y la app
# puede conectarse desde cualquier parte del mundo.
#
# Requisito: tener `cloudflared` instalado.
#   winget install --id Cloudflare.cloudflared
#   (si no quieres instalar nada, este script te dice cómo)
# ============================================================

Write-Host ""
Write-Host "  Exodo Backend - Cloudflare Tunnel" -ForegroundColor Cyan
Write-Host "  =====================================" -ForegroundColor Cyan
Write-Host ""

$backendPort = if ($env:PORT) { $env:PORT } else { 3000 }
$backendHost = if ($env:BACKEND_HOST) { $env:BACKEND_HOST } else { "0.0.0.0" }

# Verificar que cloudflared está instalado.
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
    Write-Host "  [X] cloudflared NO esta instalado." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Opciones para instalarlo:" -ForegroundColor Yellow
    Write-Host "    1. winget install --id Cloudflare.cloudflared" -ForegroundColor White
    Write-Host "    2. scoop install cloudflared" -ForegroundColor White
    Write-Host "    3. Descarga desde https://github.com/cloudflare/cloudflared/releases" -ForegroundColor White
    Write-Host ""
    Write-Host "  Una vez instalado, vuelve a correr este script." -ForegroundColor Yellow
    exit 1
}

# Verificar que el backend está corriendo en localhost.
$portCheck = Test-NetConnection -ComputerName 127.0.0.1 -Port $backendPort -WarningAction SilentlyContinue
if (-not $portCheck.TcpTestSucceeded) {
    Write-Host "  [!] Nada escucha en localhost:$backendPort" -ForegroundColor Yellow
    Write-Host "      Arranca primero el backend en otra terminal:" -ForegroundColor Yellow
    Write-Host "      npm run dev" -ForegroundColor White
    Write-Host ""
    $continue = Read-Host "  Abrir tunel de todas formas? (s/n)"
    if ($continue -ne "s") { exit 1 }
}

Write-Host "  [OK] cloudflared: $($cf.Source)" -ForegroundColor Green
Write-Host "  [OK] Backend: http://$backendHost`:$backendPort" -ForegroundColor Green
Write-Host ""
Write-Host "  Abriendo tunel HTTPS (Ctrl+C para cerrar)..." -ForegroundColor Cyan
Write-Host "  La URL HTTPS aparecera abajo. Copiala y pasala a flutter run:" -ForegroundColor Cyan
Write-Host ""
Write-Host "    flutter run -d LMV600TMe5979248 --no-pub --dart-define=BACKEND_URL=https://TU-URL.trycloudflare.com" -ForegroundColor Yellow
Write-Host ""

# Crear tunel temporal (sin login, sin cuenta Cloudflare).
# Usamos 127.0.0.1 en vez de localhost para evitar que Windows intente conectar por IPv6 (::1).
cloudflared tunnel --url "http://127.0.0.1:$backendPort"