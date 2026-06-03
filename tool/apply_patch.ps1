# Apply youtube_explode_dart InnerTube client patch
# Run after `flutter pub upgrade` if the patch is overwritten.

$target = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\youtube_explode_dart-3.1.0\lib\src\reverse_engineering\youtube_http_client.dart"

if (-not (Test-Path $target)) {
  Write-Host "File not found: $target" -ForegroundColor Red
  exit 1
}

$content = Get-Content $target -Raw

$old = "'clientName': `"WEB`",`r`n          'clientVersion': `"2.20250501.00.00`""
$new = "'clientName': `"WEB`",`r`n          'clientVersion': `"2.20250601.00.00`""

if ($content -match [regex]::Escape($old)) {
  $content = $content -replace [regex]::Escape($old), $new
  Set-Content $target $content
  Write-Host "Patch applied successfully." -ForegroundColor Green
} elseif ($content -match "'clientName': `"WEB`",`r`n          'clientVersion': `"2.20250601.00.00`"") {
  Write-Host "Patch is already up-to-date." -ForegroundColor Yellow
} else {
  Write-Host "Could not find the expected pattern. The file may have a different format." -ForegroundColor Red
}
