# start_all.ps1
$ErrorActionPreference = 'SilentlyContinue'
$base = 'C:\Users\Administrator\Documents\agi\douyin_auto'
$cfg = Get-Content (Join-Path $base 'instances.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ids = @($cfg.instances | Where-Object { -not $_.builtin } | ForEach-Object { $_.id })
$waited = 0
while ((Get-Process douyinim).Count -lt 3 -and $waited -lt 60) { Start-Sleep -Seconds 5; $waited += 5 }
foreach ($n in $ids) {
    $exe = Join-Path $base "instance$n"
    $exe = Join-Path $exe '1.1.33\douyinim.exe'
    if (Test-Path $exe) { Start-Process explorer.exe $exe; Start-Sleep -Seconds 15 }
}
