# Generates the program icon (installer\mp4rotate.ico): a rounded blue-to-violet tile with
# a white clockwise arrow circling "MP4". Used for Setup, the uninstaller / Apps & Features
# entry, and mp4rotate.exe. Sizes up to 24px drop the text (unreadable that small).
#   powershell -ExecutionPolicy Bypass -File tools\make-appicon.ps1

Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

function New-AppIconBitmap([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'

    # Rounded tile with a diagonal gradient.
    $m = [Math]::Max(0.5, $Size * 0.03)
    $rad = $Size * 0.22
    $rect = New-Object System.Drawing.RectangleF ([single]$m), ([single]$m), ([single]($Size - 2 * $m)), ([single]($Size - 2 * $m))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $rad
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $top = [System.Drawing.Color]::FromArgb(255, 0x1E, 0x88, 0xE5)
    $bottom = [System.Drawing.Color]::FromArgb(255, 0x6A, 0x2C, 0xD8)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 45.0
    $g.FillPath($grad, $path)

    # Subtle top highlight for depth.
    $hlRect = New-Object System.Drawing.RectangleF $rect.X, ($rect.Y - 1), $rect.Width, ($rect.Height * 0.5 + 2)
    $hl = New-Object System.Drawing.Drawing2D.LinearGradientBrush $hlRect, ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(0, 255, 255, 255)), 90.0
    $g.SetClip($path)
    $g.FillRectangle($hl, $rect.X, $rect.Y, $rect.Width, $rect.Height * 0.5)
    $g.ResetClip()

    # White clockwise arrow: 290-degree arc, gap at top right, arrowhead at the top pointing right.
    $white = [System.Drawing.Color]::White
    $small = $Size -le 24
    $c = $Size / 2.0
    $r = $Size * ($(if ($small) { 0.27 } else { 0.31 }))
    $w = [Math]::Max(1.5, $Size * ($(if ($small) { 0.10 } else { 0.065 })))
    $cy = $c + $Size * 0.02
    $pen = New-Object System.Drawing.Pen $white, $w
    $pen.StartCap = 'Round'
    $g.DrawArc($pen, [single]($c - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), 340, 290)
    $ex = $c; $ey = $cy - $r
    $h = $w * ($(if ($small) { 2.4 } else { 2.9 }))
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([single]($ex + $h * 0.8)), ([single]$ey)),
        (New-Object System.Drawing.PointF ([single]($ex - $h * 0.2)), ([single]($ey - $h * 0.62))),
        (New-Object System.Drawing.PointF ([single]($ex - $h * 0.2)), ([single]($ey + $h * 0.62)))
    )
    $g.FillPolygon((New-Object System.Drawing.SolidBrush $white), $pts)

    # "MP4" inside the circle, scaled to fit.
    if (-not $small) {
        $family = try { New-Object System.Drawing.FontFamily 'Segoe UI Black' } catch { New-Object System.Drawing.FontFamily 'Segoe UI' }
        $style = [System.Drawing.FontStyle]::Bold
        $target = $r * 1.32
        $sf = [System.Drawing.StringFormat]::GenericTypographic
        $em = 100.0
        $tp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $tp.AddString('MP4', $family, [int]$style, [single]$em, (New-Object System.Drawing.PointF 0, 0), $sf)
        $b = $tp.GetBounds()
        $scale = $target / $b.Width
        $mx = New-Object System.Drawing.Drawing2D.Matrix
        $mx.Translate([single]($c - ($b.X + $b.Width / 2) * $scale), [single]($cy - ($b.Y + $b.Height / 2) * $scale))
        $mx.Scale([single]$scale, [single]$scale)
        $tp.Transform($mx)
        $g.FillPath((New-Object System.Drawing.SolidBrush $white), $tp)
    }
    $g.Dispose()
    return $bmp
}

# Classic BMP (DIB) icon entry: BITMAPINFOHEADER + bottom-up BGRA + AND mask.
function Get-DibBytes($bmp) {
    $n = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $maskStride = [int]([Math]::Ceiling($n / 32.0) * 4)
    $bw.Write([uint32]40); $bw.Write([int32]$n); $bw.Write([int32]($n * 2))
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]0)
    $bw.Write([uint32]($n * $n * 4 + $maskStride * $n)); $bw.Write([int32]0); $bw.Write([int32]0)
    $bw.Write([uint32]0); $bw.Write([uint32]0)
    for ($y = $n - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $n; $x++) {
            $px = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$px.B); $bw.Write([byte]$px.G); $bw.Write([byte]$px.R); $bw.Write([byte]$px.A)
        }
    }
    $bw.Write((New-Object byte[] ($maskStride * $n)))   # all-zero AND mask; alpha does the work
    $bw.Flush()
    return , $ms.ToArray()
}

function Get-PngBytes($bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$images = foreach ($s in $sizes) {
    $bmp = New-AppIconBitmap $s
    # 256 as PNG (standard); smaller sizes as classic DIBs for maximum compatibility.
    if ($s -ge 256) { , (Get-PngBytes $bmp) } else { , (Get-DibBytes $bmp) }
}

$out = Join-Path $root 'installer\mp4rotate.ico'
$fs = [System.IO.File]::Create($out)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$images[$i].Length); $bw.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($img in $images) { $bw.Write($img) }
$bw.Close()
Write-Host "Wrote $out"
