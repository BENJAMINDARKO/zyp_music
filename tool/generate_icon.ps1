Add-Type -AssemblyName System.Drawing

$size = 192
$cell = 16
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'None'
$g.InterpolationMode = 'NearestNeighbor'

$green = [System.Drawing.Color]::FromArgb(0x1D, 0xB9, 0x54)
$white = [System.Drawing.Color]::White
$dark  = [System.Drawing.Color]::FromArgb(0x12, 0x12, 0x12)
$surface = [System.Drawing.Color]::FromArgb(0x1E, 0x1E, 0x1E)

$bgBrush  = New-Object System.Drawing.SolidBrush($green)
$playBrush = New-Object System.Drawing.SolidBrush($white)
$cornerBrush = New-Object System.Drawing.SolidBrush($dark)
$hsBgBrush = New-Object System.Drawing.SolidBrush($surface)
$hsFgBrush = New-Object System.Drawing.SolidBrush($green)

$pixels = @(
    @(0,0,1,1,1,1,1,1,1,1,0,0),
    @(0,1,1,1,1,1,1,1,1,1,1,0),
    @(1,1,1,1,1,0,0,1,1,1,1,1),
    @(1,1,1,1,0,0,0,0,1,1,1,1),
    @(1,1,1,0,0,0,0,0,0,1,1,1),
    @(1,1,1,0,0,0,0,0,0,1,1,1),
    @(1,1,1,1,0,0,0,0,1,1,1,1),
    @(1,1,1,1,1,0,0,1,1,1,1,1),
    @(0,1,1,1,1,1,1,1,1,1,1,0),
    @(0,0,1,1,1,1,1,1,1,1,0,0)
)

$corners = @(
    @(0,0,1,1,1,1,1,1,1,1,0,0),
    @(0,1,1,1,1,1,1,1,1,1,1,0),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(1,1,1,1,1,1,1,1,1,1,1,1),
    @(0,1,1,1,1,1,1,1,1,1,1,0),
    @(0,0,1,1,1,1,1,1,1,1,0,0)
)

for ($r = 0; $r -lt 10; $r++) {
    for ($c = 0; $c -lt 12; $c++) {
        $x = $c * $cell
        $y = $r * $cell
        if ($corners[$r][$c] -eq 0) {
            $g.FillRectangle($cornerBrush, $x, $y, $cell, $cell)
        } elseif ($pixels[$r][$c] -eq 1) {
            $g.FillRectangle($bgBrush, $x, $y, $cell, $cell)
        } else {
            $g.FillRectangle($playBrush, $x, $y, $cell, $cell)
        }
    }
}

# headset badge bottom-right
$hsX = 120; $hsY = 120; $hsSize = 60
$g.FillEllipse($hsBgBrush, $hsX, $hsY, $hsSize, $hsSize)

$pen = New-Object System.Drawing.Pen($green, 5)
$g.DrawArc($pen, $hsX+14, $hsY+10, 32, 24, -180, 180)

$g.FillEllipse($hsFgBrush, $hsX+8, $hsY+26, 14, 22)
$g.FillEllipse($hsFgBrush, $hsX+38, $hsY+26, 14, 22)

$bgBrush.Dispose(); $playBrush.Dispose(); $cornerBrush.Dispose()
$hsBgBrush.Dispose(); $hsFgBrush.Dispose(); $pen.Dispose()
$g.Dispose()
$bmp.Save("$PSScriptRoot\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Icon saved: $PSScriptRoot\icon.png"
