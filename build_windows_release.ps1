$ErrorActionPreference = "Stop"

$credentialPath = Join-Path $PSScriptRoot "secrets\client_secret_2_118362286247-omq7evk3pgao7lt93cimrn908442734r.apps.googleusercontent.com.json"

if (-not (Test-Path $credentialPath)) {
    throw "OAuth認証情報が見つかりません: $credentialPath"
}

$credentials = Get-Content $credentialPath -Raw | ConvertFrom-Json

$clientId = $credentials.installed.client_id
$clientSecret = $credentials.installed.client_secret

if ([string]::IsNullOrWhiteSpace($clientId)) {
    throw "JSONに installed.client_id がありません"
}

if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    throw "JSONに installed.client_secret がありません"
}

$flutterArgs = @(
    "build"
    "windows"
    "--release"
    "--dart-define=GOOGLE_DESKTOP_CLIENT_ID=$clientId"
    "--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=$clientSecret"
)

& flutter @flutterArgs

if ($LASTEXITCODE -ne 0) {
    throw "Windowsリリースビルドに失敗しました"
}

Write-Host ""
Write-Host "Windowsリリースビルドが完了しました"
Write-Host "出力先: build\windows\x64\runner\Release"