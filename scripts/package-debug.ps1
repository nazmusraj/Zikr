$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot "dist"
$sourceApk = Join-Path $projectRoot "app\build\outputs\apk\debug\app-debug.apk"
$destinationApk = Join-Path $outputDirectory "Nur-Zikr-test.apk"

Push-Location $projectRoot
try {
    & ".\gradlew.bat" --no-daemon assembleDebug
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE."
    }

    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination $destinationApk -Force
    Write-Host "APK ready: $destinationApk"
}
finally {
    Pop-Location
}
