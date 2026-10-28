# =====================================================================
#  Servidor local para "San Roque Soporte & Web"
#  - Sirve index.html y la carpeta FOTOS desde esta misma carpeta.
#  - No necesita instalar nada: usa PowerShell, que ya viene con Windows.
#  - Soporta video (permite adelantar/atrasar el MP4).
#  - Para apagarlo: cerrar la ventana o apretar Ctrl + C.
# =====================================================================
param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$root = [System.IO.Path]::GetFullPath($root)

# Tipos de archivo que el navegador necesita conocer
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.xml'  = 'application/xml'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.webp' = 'image/webp'
    '.avif' = 'image/avif'
    '.ico'  = 'image/x-icon'
    '.mp4'  = 'video/mp4'
    '.webm' = 'video/webm'
    '.mov'  = 'video/quicktime'
    '.mp3'  = 'audio/mpeg'
    '.pdf'  = 'application/pdf'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}

# Busca un puerto libre a partir del pedido (8080, 8081, ...)
$listener = $null
for ($p = $Port; $p -lt ($Port + 20); $p++) {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://localhost:$p/")
        $l.Start()
        $listener = $l
        $Port = $p
        break
    } catch {
        if ($l) { $l.Close() }
    }
}
if (-not $listener) {
    Write-Host ''
    Write-Host '  No se pudo abrir ningun puerto entre' $Port 'y' ($Port + 19) -ForegroundColor Red
    Write-Host '  Cerra otros programas que usen esos puertos y proba de nuevo.' -ForegroundColor Red
    exit 1
}

$url = "http://localhost:$Port/"

Clear-Host
Write-Host ''
Write-Host '  =====================================================' -ForegroundColor DarkRed
Write-Host '    SAN ROQUE SOPORTE & WEB  -  Servidor local' -ForegroundColor White
Write-Host '  =====================================================' -ForegroundColor DarkRed
Write-Host ''
Write-Host '    Pagina funcionando en: ' -NoNewline
Write-Host $url -ForegroundColor Green
Write-Host '    Carpeta:               ' $root
Write-Host ''
Write-Host '    Se abre solo en el navegador.' -ForegroundColor Gray
Write-Host '    Si cambias el index.html, solo recarga la pagina (F5).' -ForegroundColor Gray
Write-Host '    Para apagar el servidor: cerra esta ventana o Ctrl + C.' -ForegroundColor Gray
Write-Host ''
Write-Host '  -----------------------------------------------------' -ForegroundColor DarkGray

Start-Process $url

function Send-Text($res, [int]$code, [string]$text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $res.StatusCode = $code
    $res.ContentType = 'text/html; charset=utf-8'
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

try {
    while ($listener.IsListening) {
        # Espera pedidos sin bloquear, asi Ctrl + C funciona
        $task = $listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(300)) { }
        $ctx = $task.GetAwaiter().GetResult()
        $req = $ctx.Request
        $res = $ctx.Response
        $status = 200

        try {
            $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
            if ($path.EndsWith('/')) { $path += 'index.html' }

            $full = [System.IO.Path]::GetFullPath((Join-Path $root ($path.TrimStart('/').Replace('/', '\'))))

            # Seguridad: no permitir salir de la carpeta del proyecto
            if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $status = 403
                Send-Text $res 403 '<h1>403 - Acceso no permitido</h1>'
            }
            elseif (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $status = 404
                Send-Text $res 404 "<h1>404 - No encontrado</h1><p>$path</p>"
            }
            else {
                $ext = [System.IO.Path]::GetExtension($full).ToLower()
                $type = $mime[$ext]
                if (-not $type) { $type = 'application/octet-stream' }

                $res.ContentType = $type
                $res.AddHeader('Accept-Ranges', 'bytes')
                $res.AddHeader('Cache-Control', 'no-cache')   # siempre muestra la ultima version

                $fs = [System.IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
                try {
                    $size = $fs.Length
                    $start = 0L
                    $end = $size - 1

                    # Pedidos parciales (los usa el navegador para el video)
                    $range = $req.Headers['Range']
                    if ($range -and $range -match '^bytes=(\d*)-(\d*)$') {
                        if ($Matches[1] -ne '') { $start = [int64]$Matches[1] }
                        if ($Matches[2] -ne '') { $end = [int64]$Matches[2] }
                        if ($Matches[1] -eq '' -and $Matches[2] -ne '') {   # "bytes=-500" = ultimos 500
                            $start = [Math]::Max(0, $size - [int64]$Matches[2]); $end = $size - 1
                        }
                        if ($end -ge $size) { $end = $size - 1 }
                        if ($start -gt $end) {
                            $status = 416
                            $res.StatusCode = 416
                            $res.AddHeader('Content-Range', "bytes */$size")
                            $res.ContentLength64 = 0
                            throw [System.OperationCanceledException]::new('rango invalido')
                        }
                        $status = 206
                        $res.StatusCode = 206
                        $res.AddHeader('Content-Range', "bytes $start-$end/$size")
                    }

                    $length = $end - $start + 1
                    $res.ContentLength64 = $length
                    if ($req.HttpMethod -ne 'HEAD') {
                        $fs.Seek($start, 'Begin') | Out-Null
                        $buffer = New-Object byte[] 65536
                        $left = $length
                        while ($left -gt 0) {
                            $n = $fs.Read($buffer, 0, [int][Math]::Min($buffer.Length, $left))
                            if ($n -le 0) { break }
                            $res.OutputStream.Write($buffer, 0, $n)
                            $left -= $n
                        }
                    }
                }
                finally { $fs.Close() }
            }
        }
        catch [System.OperationCanceledException] { }
        catch {
            # El navegador corto la conexion (pasa seguido con videos): no es un error real
        }
        finally {
            try { $res.Close() } catch { }
        }

        $color = 'DarkGray'
        if ($status -ge 400) { $color = 'Yellow' }
        Write-Host ('  {0}  {1,-4} {2}  {3}' -f (Get-Date -Format 'HH:mm:ss'), $status, $req.HttpMethod, $req.Url.AbsolutePath) -ForegroundColor $color
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Host ''
    Write-Host '  Servidor apagado.' -ForegroundColor DarkRed
}
