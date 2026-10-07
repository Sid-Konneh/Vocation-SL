# Builds both apps for web and Android with Supabase connected.
# Usage: powershell -File tool/build_all.ps1 -Url https://xyz.supabase.co -Key sb_publishable_...
param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Key, [switch]$SkipApk)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$defs = @("--dart-define=SUPABASE_URL=$Url", "--dart-define=SUPABASE_PUBLISHABLE_KEY=$Key")
$version = (Select-String pubspec.yaml -Pattern '^version: (\S+)\+').Matches[0].Groups[1].Value
$enc = New-Object System.Text.UTF8Encoding($false)

function Copy-Web($dest) {
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory $dest | Out-Null }
  Get-ChildItem $dest | ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
  Copy-Item -Recurse -Force build\web\* $dest
}

Write-Output "== Job seeker web"
flutter build web --release @defs | Select-Object -Last 1
Copy-Web 'deploy\web'

Write-Output "== Employer web"
flutter build web --release -t lib/main_employer.dart @defs | Select-Object -Last 1
foreach ($f in 'build\web\index.html', 'build\web\manifest.json') {
  $t = [IO.File]::ReadAllText((Resolve-Path $f)).Replace('<title>Vocation SL</title>', '<title>Vocation SL for Employers</title>').Replace('"name": "Vocation SL"', '"name": "Vocation SL for Employers"').Replace('"short_name": "Vocation SL"', '"short_name": "VSL Employers"')
  [IO.File]::WriteAllText((Resolve-Path $f), $t, $enc)
}
Copy-Web 'employer_site\web'

if (-not $SkipApk) {
  New-Item -ItemType Directory -Force release | Out-Null
  Write-Output "== Job seeker APK"
  flutter build apk --release --flavor seeker @defs | Select-Object -Last 1
  Copy-Item build\app\outputs\flutter-apk\app-seeker-release.apk "release\vocation-sl-v$version.apk" -Force
  Write-Output "== Employer APK"
  flutter build apk --release --flavor employer -t lib/main_employer.dart @defs | Select-Object -Last 1
  Copy-Item build\app\outputs\flutter-apk\app-employer-release.apk "release\vocation-sl-employer-v$version.apk" -Force
  Get-ChildItem release | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize | Out-String | Write-Output
}
Write-Output "== Done"
