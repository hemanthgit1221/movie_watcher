# Use project-local Flutter SDK when present; otherwise system flutter.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$FlutterBin = Join-Path $RepoRoot ".tools\flutter\bin"
if (Test-Path (Join-Path $FlutterBin "flutter.bat")) {
    $env:Path = "$FlutterBin;$env:Path"
}
& flutter @args
