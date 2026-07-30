# Dev-Werkzeug: erzeugt assets\winzii.ico im haZii-Design.
# Ein dunkles, abgerundetes Quadrat mit cyanfarbenem Z — angelehnt an das
# hZ-Zeichen von hazii.org.
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'assets\winzii.ico'
$fontDir = Join-Path $root 'assets\fonts'

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = @()

# Mitgelieferte Schrift privat laden, damit das Zeichen überall gleich aussieht
$privateFonts = New-Object Drawing.Text.PrivateFontCollection
$monoPath = Join-Path $fontDir 'JetBrainsMono-Bold.ttf'
$fontFamily = $null
if (Test-Path -LiteralPath $monoPath) {
    $privateFonts.AddFontFile($monoPath)
    $fontFamily = $privateFonts.Families[0]
} else {
    $fontFamily = New-Object Drawing.FontFamily('Consolas')
}

foreach ($size in $sizes) {
    $bitmap = New-Object Drawing.Bitmap($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $graphics.TextRenderingHint = 'AntiAliasGridFit'
    $graphics.Clear([Drawing.Color]::Transparent)

    # Abgerundetes Quadrat als Hintergrund
    $radius = [math]::Max(2, [int]($size * 0.22))
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($size - $diameter - 1, 0, $diameter, $diameter, 270, 90)
    $path.AddArc($size - $diameter - 1, $size - $diameter - 1, $diameter, $diameter, 0, 90)
    $path.AddArc(0, $size - $diameter - 1, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    $background = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 10, 10, 15))
    $graphics.FillPath($background, $path)

    $borderPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(60, 0, 212, 255), [math]::Max(1, $size / 64))
    $graphics.DrawPath($borderPen, $path)

    # Z in Cyan
    $fontSize = $size * 0.62
    $font = New-Object Drawing.Font($fontFamily, $fontSize, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $format = New-Object Drawing.StringFormat
    $format.Alignment = 'Center'
    $format.LineAlignment = 'Center'
    $textBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 0, 212, 255))
    $rect = New-Object Drawing.RectangleF(0, -($size * 0.04), $size, $size)
    $graphics.DrawString('Z', $font, $textBrush, $rect, $format)

    $graphics.Dispose()
    $images += $bitmap
}

# ICO von Hand zusammensetzen: Header, Verzeichnis, danach die PNG-Daten
$stream = [IO.File]::Create($target)
$writer = New-Object IO.BinaryWriter($stream)

$writer.Write([uint16]0)               # reserviert
$writer.Write([uint16]1)               # Typ 1 = Icon
$writer.Write([uint16]$images.Count)

$offset = 6 + (16 * $images.Count)
$payloads = @()

foreach ($image in $images) {
    $memory = New-Object IO.MemoryStream
    $image.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
    $bytes = $memory.ToArray()
    $memory.Dispose()
    $payloads += , $bytes

    $dimension = if ($image.Width -ge 256) { 0 } else { $image.Width }
    $writer.Write([byte]$dimension)     # Breite
    $writer.Write([byte]$dimension)     # Höhe
    $writer.Write([byte]0)              # Farbpalette
    $writer.Write([byte]0)              # reserviert
    $writer.Write([uint16]1)            # Ebenen
    $writer.Write([uint16]32)           # Bit pro Bildpunkt
    $writer.Write([uint32]$bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $bytes.Length
}

foreach ($payload in $payloads) { $writer.Write($payload) }

$writer.Flush()
$writer.Close()
$stream.Close()
foreach ($image in $images) { $image.Dispose() }

Write-Host "  Icon erzeugt: $target ($([math]::Round((Get-Item $target).Length / 1KB)) KB, $($sizes.Count) Größen)" -ForegroundColor Cyan
