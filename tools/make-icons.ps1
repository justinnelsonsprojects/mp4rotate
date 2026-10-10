# Generates the context-menu icons (shell\icons\*.ico) and the MSIX package logos
# (package\Assets\*.png). The output is checked in; rerun only to change the artwork.
#   powershell -ExecutionPolicy Bypass -File tools\make-icons.ps1

Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

# $Kind 'right': a 280-degree arc with the gap at the top right and the arrowhead at the
# top pointing right (clockwise). 'left' is its mirror image. '180': a half-circle U-turn
# over the top with the arrowhead at the right end pointing down.
function New-RotateBitmap([int]$Size, [System.Drawing.Color]$Color, [string]$Kind) {
    if ($Kind -eq '180') { return New-Rotate180Bitmap $Size $Color }
    $Mirror = $Kind -eq 'left'
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    if ($Mirror) { $g.TranslateTransform($Size, 0); $g.ScaleTransform(-1, 1) }

    $c = $Size / 2.0
    $r = $Size * 0.30
    $w = [Math]::Max(1.4, $Size * 0.095)
    $pen = New-Object System.Drawing.Pen $Color, $w
    $g.DrawArc($pen, [single]($c - $r), [single]($c - $r + $Size * 0.04), [single](2 * $r), [single](2 * $r), 350, 280)

    # Arc ends at 270 degrees (top), travelling clockwise, i.e. pointing in +x.
    $ex = $c; $ey = $c - $r + $Size * 0.04
    $h = $w * 2.6
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([single]($ex + $h * 0.75)), ([single]$ey)),
        (New-Object System.Drawing.PointF ([single]($ex - $h * 0.25)), ([single]($ey - $h * 0.65))),
        (New-Object System.Drawing.PointF ([single]($ex - $h * 0.25)), ([single]($ey + $h * 0.65)))
    )
    $g.FillPolygon((New-Object System.Drawing.SolidBrush $Color), $pts)
    $g.Dispose()
    return $bmp
}

function New-Rotate180Bitmap([int]$Size, [System.Drawing.Color]$Color) {
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'

    $c = $Size / 2.0
    $r = $Size * 0.30
    $w = [Math]::Max(1.4, $Size * 0.095)
    $cy = $c + $Size * 0.06
    $pen = New-Object System.Drawing.Pen $Color, $w
    $g.DrawArc($pen, [single]($c - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), 180, 180)
    # Left-end tail so it reads as a U-turn rather than a bare arc.
    $g.DrawLine($pen, [single]($c - $r), [single]$cy, [single]($c - $r), [single]($cy + $Size * 0.14))

    # Arc ends at 0 degrees (right side), travelling clockwise, i.e. pointing in +y.
    $ex = $c + $r; $ey = $cy + $Size * 0.06
    $h = $w * 2.6
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([single]$ex), ([single]($ey + $h * 0.75))),
        (New-Object System.Drawing.PointF ([single]($ex - $h * 0.65)), ([single]($ey - $h * 0.25))),
        (New-Object System.Drawing.PointF ([single]($ex + $h * 0.65)), ([single]($ey - $h * 0.25)))
    )
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $Color), [single]($ex - $w / 2), [single]$cy, [single]$w, [single]($ey - $cy))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush $Color), $pts)
    $g.Dispose()
    return $bmp
}

function Get-PngBytes($bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()
}

# Writes a multi-resolution .ico whose images are PNG-compressed (supported since Vista).
function Write-Ico([string]$Path, [System.Drawing.Color]$Color, [string]$Kind) {
    $sizes = 16, 20, 24, 32, 40, 48, 64, 256
    $pngs = foreach ($s in $sizes) { , (Get-PngBytes (New-RotateBitmap $s $Color $Kind)) }
    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Close()
}

$dark  = [System.Drawing.Color]::FromArgb(255, 0x1F, 0x1F, 0x1F)   # glyph for light-theme menus
$light = [System.Drawing.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)   # glyph for dark-theme menus
$blue  = [System.Drawing.Color]::FromArgb(255, 0x00, 0x67, 0xC0)

$icons = Join-Path $root 'shell\icons'
New-Item -ItemType Directory -Force $icons | Out-Null
foreach ($kind in 'right', 'left', '180') {
    Write-Ico (Join-Path $icons "rotate_${kind}_dark.ico")  $dark  $kind
    Write-Ico (Join-Path $icons "rotate_${kind}_light.ico") $light $kind
}

$assets = Join-Path $root 'package\Assets'
New-Item -ItemType Directory -Force $assets | Out-Null
foreach ($a in @(@('Square44x44Logo.png', 44), @('Square150x150Logo.png', 150), @('StoreLogo.png', 50))) {
    (New-RotateBitmap $a[1] $blue 'right').Save((Join-Path $assets $a[0]), [System.Drawing.Imaging.ImageFormat]::Png)
}
# Inno Setup's top-right wizard image (WizardSmallImageFile): blue arrow on white, 55x55.
$small = New-Object System.Drawing.Bitmap 55, 55
$g = [System.Drawing.Graphics]::FromImage($small)
$g.Clear([System.Drawing.Color]::White)
$g.DrawImage((New-RotateBitmap 55 $blue 'right'), 0, 0)
$g.Dispose()
$small.Save((Join-Path $root 'installer\SetupSmall.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp)

Write-Host "Icons written to $icons, $assets and installer\SetupSmall.bmp"
