# Prepare the six visually inspected 512px panels; exclude their divider lines.
# Preserve a 128px texture per panel, split into sixteen 32px TileSet regions.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $root 'assets/art/effects/terrain/battlefield_biome/ChatGPT Image Oct 21, 2026, 07_17_37 PM-1.png'
$targetPath = Join-Path $root 'assets/art/effects/terrain/battlefield_biome/prepared/battlefield_ground_atlas.png'
$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$target = New-Object System.Drawing.Bitmap 768,128
try {
    for ($panel = 0; $panel -lt 6; $panel++) {
        $originX = ($panel % 3) * 512
        $originY = [math]::Floor($panel / 3) * 512
        for ($y = 0; $y -lt 128; $y++) {
            for ($x = 0; $x -lt 128; $x++) {
                $sampleX = $originX + 8 + [math]::Floor($x * 496 / 128)
                $sampleY = $originY + 8 + [math]::Floor($y * 496 / 128)
                $target.SetPixel($panel * 128 + $x, $y, $source.GetPixel($sampleX, $sampleY))
            }
        }
    }
    $target.Save($targetPath)
} finally {
    $target.Dispose()
    $source.Dispose()
}
