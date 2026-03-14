param(
  [Parameter(Mandatory=$true)][string]$SelfDir,
  [Parameter(Mandatory=$false)][string]$SteamAppId = "2379780",
  [Parameter(Mandatory=$false)][string]$WaitProcessName = "Balatro"
)

$ErrorActionPreference = "Stop"

function Read-Json([string]$path) {
  return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Ensure-Dir([string]$path) { if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path | Out-Null } }
function Save-JsonNoBom([string]$path, $obj) {
  $json = ($obj | ConvertTo-Json -Depth 12)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

$SelfDir = $SelfDir.Trim().Trim('"')
$pendingPath = Join-Path $SelfDir "pending_apply.json"
if (-not (Test-Path -LiteralPath $pendingPath)) { exit 0 }

# Wait for Balatro to exit so DLL/file locks are gone
$deadline = (Get-Date).AddMinutes(3)
while ($true) {
  $p = Get-Process -Name $WaitProcessName -ErrorAction SilentlyContinue
  if (-not $p) { break }
  if ((Get-Date) -gt $deadline) { break }
  Start-Sleep -Milliseconds 400
}

$pending = Read-Json $pendingPath
$tasks = @()
if ($pending.tasks) { $tasks = $pending.tasks }

$log = @{
  applied_at = (Get-Date).ToString("o")
  results = @()
  errors = @()
}

function Backup-File([string]$dst) {
  if (-not (Test-Path -LiteralPath $dst)) { return $null }
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $bak = "$dst.bak_$stamp"
  Copy-Item -LiteralPath $dst -Destination $bak -Force
  return $bak
}

function Backup-FolderToZip([string]$folderPath, [string]$label, [string]$backupRoot) {
  if (-not (Test-Path -LiteralPath $folderPath)) { return $null }
  Ensure-Dir $backupRoot
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $zip = Join-Path $backupRoot "$label-$stamp.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  Compress-Archive -Path (Join-Path $folderPath "*") -DestinationPath $zip -Force
  return $zip
}

foreach ($t in $tasks) {
  try {
    if ($t.type -eq "copy_file") {
      $src = [string]$t.src
      $dst = [string]$t.dst
      if (-not (Test-Path -LiteralPath $src)) { throw "missing src '$src'" }
      $bak = Backup-File $dst
      Ensure-Dir ([IO.Path]::GetDirectoryName($dst))
      Copy-Item -LiteralPath $src -Destination $dst -Force
      $log.results += "copied: $src -> $dst" + ($(if($bak){" (backup: $bak)"}else{""}))
    } elseif ($t.type -eq "replace_dir") {
      $src = [string]$t.src
      $dst = [string]$t.dst
      if (-not (Test-Path -LiteralPath $src)) { throw "missing src dir '$src'" }
      $backupRoot = if ($t.backup_root) { [string]$t.backup_root } else { Join-Path $SelfDir "_framework_backups" }
      $label = if ($t.label) { [string]$t.label } else { "dirbackup" }
      $zip = Backup-FolderToZip $dst $label $backupRoot
      if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
      Ensure-Dir $dst
      Copy-Item -Path (Join-Path $src "*") -Destination $dst -Recurse -Force
      $log.results += "replaced dir: $dst from $src" + ($(if($zip){" (backup: $zip)"}else{""}))
    }
  } catch {
    $log.errors += "Failed task $($t.type): $($_.Exception.Message)"
  }
}

try { Save-JsonNoBom (Join-Path $SelfDir "pending_apply_log.json") $log } catch {}

try { Remove-Item -LiteralPath $pendingPath -Force } catch {}
try { if ($pending.pending_root -and (Test-Path -LiteralPath $pending.pending_root)) { Remove-Item -LiteralPath $pending.pending_root -Recurse -Force -ErrorAction SilentlyContinue } } catch {}

if ($SteamAppId -and $SteamAppId.Trim() -ne "") {
  try { Start-Process ("steam://rungameid/" + $SteamAppId) | Out-Null } catch {}
}
