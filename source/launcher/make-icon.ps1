# Dessine le logo de GameBoost et ecrit GameBoost.ico (16 a 256 px) + logo.png (512 px, pour le README).
# Aucune image externe : tout est trace ici, donc le logo se modifie en changeant ces quelques lignes.
param([string]$OutDir = $PSScriptRoot)
Add-Type -AssemblyName System.Drawing

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}

# Trace le logo dans un carre de $n pixels. $simple = petites tailles : eclair seul, plus gros.
function New-Logo([int]$n, [bool]$simple) {
    $bm = New-Object System.Drawing.Bitmap($n, $n, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bm)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([System.Drawing.Color]::Transparent)
    $u = $n / 100.0
    $cyan = [System.Drawing.Color]::FromArgb(34, 211, 238); $green = [System.Drawing.Color]::FromArgb(46, 232, 143)

    # Fond : carre arrondi bleu nuit, leger degrade
    $m = 4 * $u; $side = $n - 2 * $m
    $bg = New-RoundRect $m $m $side $side (22 * $u)
    $rect = New-Object System.Drawing.RectangleF($m, $m, $side, $side)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(27, 33, 56), [System.Drawing.Color]::FromArgb(9, 12, 22), 90.0)
    $g.FillPath($br, $bg); $br.Dispose()
    # Lisere lumineux
    $bp = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(150, $cyan), [System.Drawing.Color]::FromArgb(40, $green), 60.0)
    $pen = New-Object System.Drawing.Pen($bp, [single][math]::Max(1.0, 1.6 * $u)); $g.DrawPath($pen, $bg); $pen.Dispose(); $bp.Dispose()

    if (-not $simple) {
        # Compteur : arc de 270 degres, rempli aux trois quarts (le "boost")
        $ringR = 33 * $u; $cx = 50 * $u; $cy = 52 * $u; $th = 6.5 * $u
        $rr = New-Object System.Drawing.RectangleF(($cx - $ringR), ($cy - $ringR), (2 * $ringR), (2 * $ringR))
        $track = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48, 255, 255, 255), [single]$th)
        $track.StartCap = 'Round'; $track.EndCap = 'Round'; $g.DrawArc($track, $rr, 135, 270); $track.Dispose()
        $gr = New-Object System.Drawing.RectangleF(($cx - $ringR - $th), ($cy - $ringR - $th), (2 * ($ringR + $th)), (2 * ($ringR + $th)))
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gr, $cyan, $green, 0.0)
        $fill = New-Object System.Drawing.Pen($gb, [single]$th); $fill.StartCap = 'Round'; $fill.EndCap = 'Round'
        $g.DrawArc($fill, $rr, 135, 205); $fill.Dispose(); $gb.Dispose()
    }

    # Eclair
    $pts = @(@(57, 14), @(27, 55), @(46, 55), @(40, 88), @(73, 43), @(53, 43))
    $s = if ($simple) { 1.12 } else { 0.74 }; $ox = 50; $oy = if ($simple) { 51 } else { 52 }
    $poly = foreach ($p in $pts) { New-Object System.Drawing.PointF(((($p[0] - 50) * $s + $ox) * $u), ((($p[1] - 51) * $s + $oy) * $u)) }
    $bolt = New-Object System.Drawing.Drawing2D.GraphicsPath; $bolt.AddPolygon([System.Drawing.PointF[]]$poly)
    if (-not $simple) {
        # Halo doux sous l'eclair
        foreach ($k in 9, 8, 7, 6, 5, 4, 3, 2, 1) {
            $hp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(7, $cyan), [single]($k * 1.5 * $u)); $hp.LineJoin = 'Round'
            $g.DrawPath($hp, $bolt); $hp.Dispose()
        }
    }
    $bb = $bolt.GetBounds()
    $lb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bb, [System.Drawing.Color]::FromArgb(190, 250, 255), $green, 70.0)
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = @([System.Drawing.Color]::FromArgb(200, 250, 255), $cyan, $green); $blend.Positions = @(0.0, 0.45, 1.0)
    $lb.InterpolationColors = $blend
    $g.FillPath($lb, $bolt); $lb.Dispose(); $bolt.Dispose(); $bg.Dispose(); $g.Dispose()
    return $bm
}

# Dessine en grand puis reduit : contours nets a toutes les tailles
function Get-LogoAt([int]$size) {
    $simple = ($size -le 24)
    $big = New-Logo ($size * 4) $simple
    $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
    $g.DrawImage($big, 0, 0, $size, $size); $g.Dispose(); $big.Dispose()
    return $out
}

# Fichier .ico : 256 px en PNG, tailles plus petites en image 32 bits classique (compatibles partout)
$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$entries = @()
foreach ($sz in $sizes) {
    $bm = Get-LogoAt $sz
    $ms = New-Object System.IO.MemoryStream
    if ($sz -ge 256) { $bm.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png) }
    else {
        $bw = New-Object System.IO.BinaryWriter($ms)
        $bw.Write([int]40); $bw.Write([int]$sz); $bw.Write([int]($sz * 2)); $bw.Write([int16]1); $bw.Write([int16]32)
        $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
        for ($y = $sz - 1; $y -ge 0; $y--) { for ($x = 0; $x -lt $sz; $x++) { $c = $bm.GetPixel($x, $y); $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A) } }
        $maskRow = [int]([math]::Ceiling($sz / 32.0) * 4)
        $bw.Write((New-Object byte[] ($maskRow * $sz))); $bw.Flush()
    }
    $entries += , @{ Size = $sz; Data = $ms.ToArray() }
    $bm.Dispose(); $ms.Dispose()
}
$ico = Join-Path $OutDir 'GameBoost.ico'
$fs = [System.IO.File]::Create($ico); $w = New-Object System.IO.BinaryWriter($fs)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
    $b = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $w.Write([byte]$b); $w.Write([byte]$b); $w.Write([byte]0); $w.Write([byte]0); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]$e.Data.Length); $w.Write([int]$offset); $offset += $e.Data.Length
}
foreach ($e in $entries) { $w.Write($e.Data) }
$w.Flush(); $fs.Close()

$png = Get-LogoAt 512; $png.Save((Join-Path $OutDir 'logo.png'), [System.Drawing.Imaging.ImageFormat]::Png); $png.Dispose()
foreach ($t in 16, 32, 48) { $b = Get-LogoAt $t; $b.Save((Join-Path $OutDir ("apercu_" + $t + ".png")), [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose() }
"logo ecrit : $ico (" + (Get-Item $ico).Length + " octets)"
