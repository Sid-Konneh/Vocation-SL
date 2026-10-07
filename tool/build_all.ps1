# Builds the web app and the Android APK with Supabase connected.
# Usage: powershell -File tool/build_all.ps1 -Url https://xyz.supabase.co -Key sb_publishable_... [-SkipApk]
param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Key, [switch]$SkipApk)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$defs = @("--dart-define=SUPABASE_URL=$Url", "--dart-define=SUPABASE_PUBLISHABLE_KEY=$Key")
$version = (Select-String pubspec.yaml -Pattern '^version: (\S+)\+').Matches[0].Groups[1].Value

Write-Output "== Web"
flutter build web --release --no-wasm-dry-run @defs | Select-Object -Last 1
if (-not (Test-Path deploy\web)) { New-Item -ItemType Directory deploy\web | Out-Null }
Get-ChildItem deploy\web | ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
Copy-Item -Recurse -Force build\web\* deploy\web

if (-not $SkipApk) {
  Write-Output "== Android APK"
  flutter build apk --release @defs | Select-Object -Last 1
  New-Item -ItemType Directory -Force release | Out-Null
  Get-ChildItem release -Filter *.apk | ForEach-Object { Remove-Item -Force $_.FullName }
  Copy-Item build\app\outputs\flutter-apk\app-release.apk "release\vocation-sl-v$version.apk" -Force
  Get-ChildItem release | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize | Out-String | Write-Output
}
Write-Output "== Done"
