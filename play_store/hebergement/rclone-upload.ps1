# =====================================================================
#  Envoi des audios vers Cloudflare R2
#  Remplissez les 4 valeurs ci-dessous, puis lancez le script.
#  Il est reprise-compatible : relancez-le autant de fois que besoin.
# =====================================================================

# ------- A RENSEIGNER -------
$AccountId   = "COLLEZ_VOTRE_ACCOUNT_ID"
$AccessKey   = "COLLEZ_VOTRE_ACCESS_KEY_ID"
$SecretKey   = "COLLEZ_VOTRE_SECRET_ACCESS_KEY"
$Bucket      = "imam-audios"
# ----------------------------

# Dossier local a envoyer (ne pas modifier)
$LocalDir = "D:\XAMP\htdocs\IMMK\Audios"
# Prefixe (dossier) dans le bucket -> donne l'URL /IMMK/audios/...
$RemotePrefix = "IMMK/audios"

# Chemin vers rclone.exe (adapte si besoin)
$Rclone = "C:\rclone\rclone.exe"

$ErrorActionPreference = "Stop"

if ($AccountId -like "COLLEZ_*" -or $AccessKey -like "COLLEZ_*" -or $SecretKey -like "COLLEZ_*") {
    Write-Host "ERREUR : renseignez d'abord AccountId, AccessKey et SecretKey en haut du script." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Rclone)) {
    $found = (Get-Command rclone -ErrorAction SilentlyContinue).Source
    if ($found) { $Rclone = $found } else {
        Write-Host "ERREUR : rclone.exe introuvable. Corrigez la variable `$Rclone ou installez rclone." -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path $LocalDir)) {
    Write-Host "ERREUR : dossier local introuvable : $LocalDir" -ForegroundColor Red
    exit 1
}

# --- Ecriture d'un fichier de configuration rclone temporaire ---
$cfg = Join-Path $env:TEMP "rclone_r2.conf"
@"
[r2]
type = s3
provider = Cloudflare
access_key_id = $AccessKey
secret_access_key = $SecretKey
endpoint = https://$AccountId.r2.cloudflarestorage.com
acl = private
"@ | Set-Content -Path $cfg -Encoding ascii

Write-Host ""
Write-Host "=== Verification de la connexion ===" -ForegroundColor Cyan
& $Rclone --config $cfg lsd "r2:$Bucket"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Connexion impossible. Verifiez AccountId / AccessKey / SecretKey / Bucket." -ForegroundColor Red
    Remove-Item $cfg -Force -ErrorAction SilentlyContinue
    exit 1
}

$size = (Get-ChildItem $LocalDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host ("=== Envoi de {0} Go vers r2:{1}/{2} ===" -f [math]::Round($size/1GB,2), $Bucket, $RemotePrefix) -ForegroundColor Cyan
Write-Host "Ne fermez pas cette fenetre. Relancez le script si besoin (il reprend)."
Write-Host ""

& $Rclone --config $cfg copy $LocalDir "r2:$Bucket/$RemotePrefix" `
    --transfers 8 --checkers 16 `
    --s3-chunk-size 64M --s3-upload-concurrency 4 `
    --retries 5 --low-level-retries 10 `
    --progress

$code = $LASTEXITCODE
Remove-Item $cfg -Force -ErrorAction SilentlyContinue

if ($code -eq 0) {
    Write-Host ""
    Write-Host "SUCCES : tous les fichiers sont envoyes." -ForegroundColor Green
    Write-Host "Testez ensuite une URL, par ex. :" -ForegroundColor Green
    Write-Host "  https://audio.imammadoukone.com/$RemotePrefix/Sira/01.mp3"
} else {
    Write-Host ""
    Write-Host "L'envoi s'est arrete avec le code $code. Relancez le script pour reprendre." -ForegroundColor Yellow
}
