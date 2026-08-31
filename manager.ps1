$Host.UI.RawUI.WindowTitle = "抖音聊天多开管理器"

# ============ UTF-8 ============
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Console]::InputEncoding  = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$base = 'C:\Users\Administrator\Documents\agi\douyin_auto'
$configFile = Join-Path $base 'instances.json'

# ============ 翻译表 ============
$countryCN = @{ 'CN'='中国'; 'HK'='香港'; 'SG'='新加坡'; 'JP'='日本'; 'US'='美国'; 'GB'='英国'; 'KR'='韩国'; 'AU'='澳大利亚' }
$cityCN = @{ 'Shenzhen'='深圳'; 'Beijing'='北京'; 'Shanghai'='上海'; 'Guangzhou'='广州'; 'Chengdu'='成都'; 'Hangzhou'='杭州'; 'Jiaxing'='嘉兴'; 'Nanjing'='南京' }
$orgMap = [ordered]@{ 'China Mobile'='中国移动'; 'China Unicom'='中国联通'; 'China Telecom'='中国电信'; 'Alibaba'='阿里云'; 'Tencent'='腾讯云'; 'Huawei'='华为云'; 'Amazon'='AWS'; 'Google'='Google'; 'Microsoft'='Microsoft' }

# ============ 表格列宽 ============
$script:nameW = 8; $script:procW = 6; $script:clientW = 6; $script:credW = 26; $script:nickW = 8
$script:innerW = ($script:nameW+2) + ($script:procW+2) + ($script:clientW+2) + ($script:credW+2) + ($script:nickW+2) + 4

function Build-Border($left, $mid, $right, $fill) {
    $w1 = $script:nameW + 2; $w2 = $script:procW + 2; $w3 = $script:clientW + 2; $w4 = $script:credW + 2; $w5 = $script:nickW + 2
    return "  $left$($fill*$w1)$mid$($fill*$w2)$mid$($fill*$w3)$mid$($fill*$w4)$mid$($fill*$w5)$right"
}

$script:borderTop = Build-Border '┌' '┬' '┐' '─'
$script:borderMid = Build-Border '├' '┬' '┤' '─'
$script:borderBot = Build-Border '└' '┴' '┘' '─'

# ============ 显示宽度工具 ============
function Get-DisplayWidth($str) {
    if (-not $str) { return 0 }
    $w = 0
    foreach ($c in $str.ToCharArray()) {
        $code = [int]$c
        if (($code -ge 0x4E00 -and $code -le 0x9FFF) -or
            ($code -ge 0x3000 -and $code -le 0x303F) -or
            ($code -ge 0xFF00 -and $code -le 0xFFEF) -or
            ($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0x2FDF) -or
            ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
            ($code -ge 0x20000 -and $code -le 0x2A6DF)) { $w += 2 }
        else { $w += 1 }
    }
    return $w
}

function Pad-Right($str, $width) {
    $dw = Get-DisplayWidth $str
    $pad = [math]::Max(0, $width - $dw)
    return $str + (' ' * $pad)
}

function Truncate-Width($str, $maxW) {
    if (-not $str) { return '' }
    $w = 0; $result = ''
    foreach ($c in $str.ToCharArray()) {
        $code = [int]$c
        $cw = if ($code -ge 0x2000) { 2 } else { 1 }
        if ($w + $cw -gt $maxW) {
            if ($w + 2 -le $maxW) { return $result + '..' }
            return $result.Substring(0, [math]::Max(0, $result.Length - 1)) + '..'
        }
        $result += $c; $w += $cw
    }
    return $result
}

function Write-BoxLine($text, $color) {
    $pad = [math]::Max(0, $script:innerW - (Get-DisplayWidth $text) - 1)
    Write-Host "  │ " -Fore DarkCyan -No
    Write-Host $text -Fore $color -No
    Write-Host (" " * $pad) -No
    Write-Host "│" -Fore DarkCyan
}

# ============ 缓存 ============
$script:credCache = @{}
$script:wmiProcs = $null
$script:dotnetProcs = $null
$script:ipCache = $null
$script:ipCacheTime = [datetime]::MinValue

function Refresh-ProcessCache {
    $script:wmiProcs = Get-CimInstance Win32_Process -Filter "Name='douyinim.exe'" -EA SilentlyContinue
    $script:dotnetProcs = Get-Process douyinim -EA SilentlyContinue
}

# ============ IO ============
function Load-Config {
    if (Test-Path $configFile) { return (Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return @{ instances = @(); nextId = 1 }
}
function Save-Config($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configFile, $json, (New-Object Text.UTF8Encoding $true))
}

function Get-InstanceByIndex($num) {
    $cfg = Load-Config; $idx = 0
    foreach ($i in $cfg.instances) {
        if (-not $i.builtin) { $idx++; if ($idx -eq $num) { return $i } }
    }
    return $null
}

# ============ 三指标检测 ============

# 指标1: 进程是否在运行
function Get-ProcessStatus($dir) {
    if ($dir -eq '') {
        foreach ($p in $script:wmiProcs) {
            if ($p.CommandLine -match 'ByteDance\\抖音聊天' -and $p.CommandLine -notmatch 'instance') { return $true }
        }
    } else {
        foreach ($p in $script:wmiProcs) {
            if ($p.CommandLine -match [regex]::Escape($dir)) { return $true }
        }
    }
    return $false
}

# 指标2: 客户端窗口状态
function Get-ClientStatus($dir) {
    if ($dir -eq '') {
        foreach ($p in $script:wmiProcs) {
            if ($p.CommandLine -match 'ByteDance\\抖音聊天' -and $p.CommandLine -notmatch 'instance') {
                $w = $script:dotnetProcs | Where { $_.MainWindowHandle -ne 0 -and $_.Id -eq $p.ProcessId }
                if ($w -and $w.MainWindowTitle -match '登录') { return 'login' }
                return 'online'
            }
        }
    } else {
        foreach ($p in $script:wmiProcs) {
            if ($p.CommandLine -match [regex]::Escape($dir)) {
                $w = $script:dotnetProcs | Where { $_.MainWindowHandle -ne 0 -and $_.Id -eq $p.ProcessId }
                if ($w -and $w.MainWindowTitle -match '登录') { return 'login' }
                return 'online'
            }
        }
    }
    return 'n/a'
}

# 指标3: 凭据状态 (所有实例都检测)
function Invoke-CredentialCheck($datadir) {
    $result = @{ Status = 'unknown'; Detail = '未知' }
    try {
        $raw = & node (Join-Path $base 'check_credential.js') $datadir 2>&1
        $json = ("$raw".Trim()) | ConvertFrom-Json -EA SilentlyContinue
        if ($json -and $json.status) {
            $result.Detail = if ($json.detail) { $json.detail } else { $json.status }
            switch ($json.status) {
                'valid'           { $result.Status = 'valid' }
                'expiring_days'   { $result.Status = 'expiring' }
                'expiring_hours'  { $result.Status = 'expiring' }
                'expired'         { $result.Status = 'expired' }
                'session_expired' { $result.Status = 'expired' }
                'locked'          { $result.Status = 'locked' }
                'no_session'      { $result.Status = 'expired' }
                'no_cookie'       { $result.Status = 'no_data' }
                'no_data'         { $result.Status = 'no_data' }
                default           { $result.Status = 'unknown' }
            }
        }
    } catch { }
    return $result
}

function Get-CredStatus($datadir) {
    $now = Get-Date
    if ($script:credCache.ContainsKey($datadir)) {
        $c = $script:credCache[$datadir]
        if (($now - $c.Time).TotalSeconds -lt 60) { return $c.Info }
    }
    $info = Invoke-CredentialCheck $datadir
    $script:credCache[$datadir] = @{ Info = $info; Time = $now }
    return $info
}

# ============ 网络 ============
function Get-PublicIP {
    if ($script:ipCache -and ((Get-Date) - $script:ipCacheTime).TotalMinutes -lt 30) { return $script:ipCache }
    $saved = [Net.WebRequest]::DefaultWebProxy
    try {
        [Net.WebRequest]::DefaultWebProxy = $null
        $r = $null
        try { $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 5 -EA Stop } catch { }
        if (-not $r) { try { $r = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=query,city,country,isp' -TimeoutSec 5 -EA Stop } catch { } }
        if (-not $r) { try { $r = Invoke-RestMethod -Uri 'https://ipwho.is/' -TimeoutSec 5 -EA Stop } catch { } }
        if ($r) {
            $ip = if ($r.ip) { $r.ip } elseif ($r.query) { $r.query } else { '?' }
            $rawCountry = if ($r.country_code) { $r.country_code } elseif ($r.country) { $r.country } else { '' }
            $cn = if ($countryCN[$rawCountry]) { $countryCN[$rawCountry] } else { $rawCountry }
            $city = if ($r.city) { if ($cityCN[$r.city]) { $cityCN[$r.city] } else { $r.city } } else { '' }
            $orgRaw = if ($r.org) { $r.org } elseif ($r.isp) { $r.isp } else { '' }
            $org = $orgRaw
            if ($org) { foreach ($k in $orgMap.Keys) { if ($orgRaw -match [regex]::Escape($k)) { $org = $orgMap[$k]; break } } }
            $loc = if ($cn -eq '中国') { $city } else { "$cn $city" }
            $script:ipCache = "$ip [$loc] $org"
            $script:ipCacheTime = Get-Date
            return $script:ipCache
        }
        return '(检测失败)'
    } catch { return '(检测失败)' }
    finally { [Net.WebRequest]::DefaultWebProxy = $saved }
}

# ============ 系统信息 ============
function Get-MemoryInfo {
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $t = [math]::Round($os.TotalVisibleMemorySize/1MB,1); $f = [math]::Round($os.FreePhysicalMemory/1MB,1)
    return @{ Total=$t; Used=[math]::Round($t-$f,1); Pct=[math]::Round(($t-$f)/$t*100,0) }
}
function Get-CpuInfo {
    $load = 0
    try { $c = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2 -EA SilentlyContinue).CounterSamples.CookedValue; $load = [math]::Round(($c | Measure-Object -Average).Average, 0) }
    catch { $load = (Get-CimInstance Win32_Processor).LoadPercentage }
    $temp = $null; $tz = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace 'root/wmi' -EA SilentlyContinue | Select -First 1
    if ($tz) { $temp = [math]::Round(($tz.CurrentTemperature - 2732)/10, 1) }
    # CPU频率
    $freq = (Get-CimInstance Win32_Processor -EA SilentlyContinue).CurrentClockSpeed
    # 风扇转速 (WMI 可能拿不到)
    $fanRpm = $null
    try {
        $fan = Get-CimInstance Win32_Fan -EA SilentlyContinue | Where-Object { $_.DesiredSpeed -gt 0 } | Select -First 1
        if ($fan) { $fanRpm = $fan.DesiredSpeed }
    } catch { }
    return @{ Load=$load; Temp=$temp; Freq=$freq; FanRpm=$fanRpm }
}

# ============ 表格行输出 ============
function Write-Row($name, $procText, $procClr, $clientText, $clientClr, $credText, $credClr, $nick) {
    $n  = Pad-Right $name $script:nameW
    $p  = Pad-Right $procText $script:procW
    $c  = Pad-Right $clientText $script:clientW
    $cr = Pad-Right (Truncate-Width $credText $script:credW) $script:credW
    $nkText = if ($nick) { $nick } else { '' }
    $nk = Pad-Right $nkText $script:nickW
    Write-Host "  │ " -Fore DarkCyan -No
    Write-Host "$n │ " -Fore White -No
    Write-Host "$p │ " -Fore $procClr -No
    Write-Host "$c │ " -Fore $clientClr -No
    Write-Host "$cr │ " -Fore $credClr -No
    Write-Host "$nk│" -Fore Yellow
}

function Write-Header {
    $h1 = Pad-Right '实例' $script:nameW
    $h2 = Pad-Right '进程' $script:procW
    $h3 = Pad-Right '客户端' $script:clientW
    $h4 = Pad-Right '凭据' $script:credW
    $h5 = Pad-Right '备注' $script:nickW
    Write-Host "  │ " -Fore DarkCyan -No
    Write-Host "$h1 │ " -Fore DarkCyan -No
    Write-Host "$h2 │ " -Fore DarkCyan -No
    Write-Host "$h3 │ " -Fore DarkCyan -No
    Write-Host "$h4 │ " -Fore DarkCyan -No
    Write-Host "$h5│" -Fore DarkCyan
}

# ============ 仪表盘 ============
function Show-Dashboard {
    $cfg = Load-Config
    Refresh-ProcessCache
    $mem = Get-MemoryInfo; $cpu = Get-CpuInfo
    $boot = (Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).LastBootUpTime
    $up = (Get-Date) - $boot
    $memColor = if ($mem.Pct -ge 90) {'Red'} elseif ($mem.Pct -ge 70) {'Yellow'} else {'Green'}
    $memBar = ('█' * [math]::Floor($mem.Pct/5)) + ('░' * (20 - [math]::Floor($mem.Pct/5)))
    $cpuColor = if ($cpu.Load -gt 90) {'Red'} elseif ($cpu.Load -gt 70) {'Yellow'} else {'Green'}
    $cpuBar = ('█' * [math]::Floor($cpu.Load/5)) + ('░' * (20 - [math]::Floor($cpu.Load/5)))
    $tempStr = if ($cpu.Temp) { "$($cpu.Temp)C" } else { 'N/A' }
    $freqStr = if ($cpu.Freq) { "$([math]::Round($cpu.Freq/1000,1))GHz" } else { 'N/A' }
    $fanStr = if ($cpu.FanRpm) { "$($cpu.FanRpm)RPM" } else { 'N/A' }
    # 温度颜色
    $tempColor = if ($cpu.Temp -and $cpu.Temp -ge 80) { 'Red' } elseif ($cpu.Temp -and $cpu.Temp -ge 60) { 'Yellow' } else { 'Green' }
    $pubIP = Get-PublicIP

    Write-Host ""
    Write-Host $script:borderTop -Fore DarkCyan
    Write-BoxLine "抖音聊天多开管理器" 'DarkCyan'
    Write-Host ("  ├" + "─" * $script:innerW + "┤") -Fore DarkCyan
    Write-BoxLine ("运行: {0}天{1}时{2}分" -f $up.Days,$up.Hours,$up.Minutes) 'White'
    Write-BoxLine "内存: $memBar $($mem.Used)/$($mem.Total)GB $($mem.Pct)%" $memColor
    Write-BoxLine "CPU:  $cpuBar $($cpu.Load)% 频率: $freqStr" $cpuColor
    Write-BoxLine "硬件: 温度 $tempStr | 风扇 $fanStr | efanapp $(if (Get-Process efanapp -EA SilentlyContinue) { '运行中' } else { '未运行' })" $tempColor
    $ipLine = "出口: $pubIP"
    if ((Get-DisplayWidth $ipLine) -gt $script:innerW - 1) { $ipLine = $ipLine.Substring(0,50) + '...' }
    Write-BoxLine $ipLine 'White'

    # 实例状态表
    Write-Host $script:borderMid -Fore DarkCyan
    Write-Header
    Write-Host $script:borderMid -Fore DarkCyan

    $allInstances = @($cfg.instances | Where { $_.builtin }) + @($cfg.instances | Where { -not $_.builtin })
    foreach ($inst in $allInstances) {
        $proc   = Get-ProcessStatus $inst.dir
        $client = Get-ClientStatus $inst.dir

        # 凭据: 所有实例都检测
        $cred = Get-CredStatus $inst.datadir

        # 运行中的实例: cookie被锁无法直接读, 看文件最后修改时间
        if ($cred.Status -eq 'locked') {
            $cookiePath = Join-Path (Join-Path $env:APPDATA $inst.datadir) 'Network\Cookies'
            $cookieAge = -1
            if (Test-Path $cookiePath) {
                $cookieAge = ((Get-Date) - (Get-Item $cookiePath).LastWriteTime).TotalMinutes
            }
            if ($client -eq 'login') {
                $cred = @{ Status = 'expired'; Detail = '需重新登录' }
            } elseif ($cookieAge -ge 0 -and $cookieAge -lt 5) {
                $cred = @{ Status = 'valid'; Detail = "有效(刷新于$([math]::Floor($cookieAge))分钟前)" }
            } elseif ($cookieAge -ge 5) {
                $cred = @{ Status = 'expiring'; Detail = "可能掉线(无刷新$([math]::Floor($cookieAge))分钟)" }
            } else {
                $cred = @{ Status = 'online'; Detail = '在线(未验证)' }
            }
        }

        $procText   = if ($proc) { '运行中' } else { '已停止' }
        $procClr    = if ($proc) { 'Green' } else { 'DarkGray' }
        $clientText = switch ($client) { 'online' { '在线' }; 'login' { '需登录' }; default { '-' } }
        $clientClr  = switch ($client) { 'online' { 'Green' }; 'login' { 'Yellow' }; default { 'DarkGray' } }
        $credText   = if ($cred.Detail) { $cred.Detail } else { '未知' }
        $credClr    = switch ($cred.Status) {
            'valid'    { 'Green' }
            'online'   { 'Cyan' }
            'expiring' { 'Yellow' }
            'expired'  { 'Red' }
            'locked'   { 'Yellow' }
            default    { 'DarkGray' }
        }

        Write-Row $inst.name $procText $procClr $clientText $clientClr $credText $credClr $inst.nick
    }

    Write-Host $script:borderBot -Fore DarkCyan
    Write-Host ""
}

# ============ 菜单 ============
function Show-Menu {
    $cfg = Load-Config

    Write-Host "  操作:" -Fore White
    Write-Host ""

    $mainNick = ($cfg.instances | Where { $_.builtin }).nick
    $mainProc = Get-ProcessStatus ''
    $mainText = if ($mainProc) { '运行中' } else { '已停止' }
    $mainClr  = if ($mainProc) { 'Green' } else { 'DarkGray' }
    Write-Host "  [M] 主实例    " -Fore White -No; Write-Host $mainText -Fore $mainClr -No
    if ($mainNick) { Write-Host "  $mainNick" -Fore Yellow -No }
    Write-Host ""

    $idx = 0
    foreach ($inst in $cfg.instances) {
        if ($inst.builtin) { continue }
        $idx++
        $proc = Get-ProcessStatus $inst.dir
        $text = if ($proc) { '运行中' } else { '已停止' }
        $clr  = if ($proc) { 'Green' } else { 'DarkGray' }
        Write-Host "  [$idx] $($inst.name)    " -Fore White -No; Write-Host $text -Fore $clr -No
        if ($inst.nick) { Write-Host "  $($inst.nick)" -Fore Yellow -No }
        Write-Host ""
    }

    Write-Host ""
    Write-Host "  [A] 全部启动  [N] 新建实例  [E] 编辑备注" -Fore Cyan
    Write-Host "  [D] 删除实例  [S] 全部停止  [R] 刷新  [Q] 退出" -Fore DarkGray
    Write-Host ""
    Write-Host "  jianhx 2026 all rights reserved" -Fore DarkGray
    Write-Host ""
}

# ============ 操作函数 ============
function Start-Instance($dir) {
    $exe = if ($dir) { Join-Path $base (Join-Path $dir '1.1.33\douyinim.exe') } else { 'C:\Program Files\ByteDance\抖音聊天\1.1.33\douyinim.exe' }
    if (Test-Path $exe) { Start-Process explorer.exe $exe; Write-Host "  启动中..." -Fore Green; Start-Sleep 3 }
    else { Write-Host "  未找到: $exe" -Fore Red; Start-Sleep 2 }
}

function New-Instance {
    $cfg = Load-Config
    $nick = Read-Host "  备注(可留空)"
    $maxId = 0; $cfg.instances | ForEach { if ($_.id -gt $maxId) { $maxId = $_.id } }; $n = $maxId + 1
    while (Test-Path (Join-Path $base "instance$n")) { $n++ }
    $dirName = "instance$n"; $dataDir = "抖音聊天$n"
    Write-Host "  创建 $dirName ($dataDir)..." -Fore Cyan
    Copy-Item (Join-Path $base 'instance2') (Join-Path $base $dirName) -Recurse -Force

    $patchJs = Join-Path $base "patch_$dirName.js"
    $escapedBase = $base -replace '\\', '\\\\'
    $jsContent = @"
const asar = require('asar'), fs = require('fs'), p = require('path');
const src = 'C:\\Program Files\\ByteDance\\抖音聊天\\1.1.33\\resources\\app.asar';
const outDir = p.join('$escapedBase', '$dirName', '1.1.33', 'resources', 'app_patched');
const outAsar = p.join('$escapedBase', '$dirName', '1.1.33', 'resources', 'app.asar');
asar.extractAll(src, outDir);
let x = fs.readFileSync(p.join(outDir, 'index.js'), 'utf8');
x = x.replace('setPath("userData",(0,m.join)(e.app.getPath("appData"),"抖音聊天")', 'setPath("userData",(0,m.join)(e.app.getPath("appData"),"$dataDir")');
x = x.replace('if(!e.app.requestSingleInstanceLock())return e.app.quit(-1),!0', 'if(!1)return e.app.quit(-1),!0');
fs.writeFileSync(p.join(outDir, 'index.js'), x, 'utf8');
asar.createPackage(outDir, outAsar).then(() => {
  console.log('done');
  fs.rmSync(outDir, {recursive:true, force:true});
});
"@
    [IO.File]::WriteAllText($patchJs, $jsContent, (New-Object Text.UTF8Encoding $false))
    Push-Location $base; node $patchJs 2>&1 | Out-Null; Pop-Location
    Remove-Item $patchJs -Force -EA SilentlyContinue
    Remove-Item (Join-Path $base "$dirName\1.1.33\resources\app_patched") -Recurse -Force -EA SilentlyContinue

    $cfg = Load-Config
    $cfg.instances += [PSCustomObject]@{ id=$n; name="小号$n"; dir=$dirName; datadir=$dataDir; nick=$nick; builtin=$false }
    $cfg.nextId = $n + 1; Save-Config $cfg
    $allIds = ($cfg.instances | Where {-not $_.builtin}).id -join ','
    $taskContent = "foreach(`$n in $allIds){`$e=Join-Path '$base' ('instance'+`$n);`$e=Join-Path `$e '1.1.33\douyinim.exe';if(Test-Path `$e){Start-Process explorer.exe `$e;Start-Sleep -Seconds 15}}"
    Set-Content (Join-Path $base 'start_all.ps1') $taskContent -Encoding UTF8
    Write-Host "  创建完成: $dirName" -Fore Green
    if ((Read-Host "  立即启动? (Y/n)") -ne 'n') { Start-Instance $dirName }
    Start-Sleep 1
}

function Edit-Nick {
    $cfg = Load-Config; Write-Host ""
    $mainNick = ($cfg.instances | Where { $_.builtin }).nick
    Write-Host "  [M] 主实例 - $(if ($mainNick) { $mainNick } else { '(无)' })" -Fore Yellow
    foreach ($i in $cfg.instances) {
        if ($i.builtin) { continue }
        $n = if ($i.nick) { $i.nick } else { '(无)' }
        Write-Host "  [$($i.id)] $($i.name) - $n" -Fore Yellow
    }
    Write-Host ""
    $id = Read-Host "  编号(M=主实例, 回车取消)"
    if ($id) {
        $nn = Read-Host "  新备注"
        foreach ($i in $cfg.instances) {
            if (($id -eq 'M' -and $i.builtin) -or ($id -match '^\d+$' -and $i.id -eq [int]$id)) {
                $i.nick = $nn; Write-Host "  已更新" -Fore Green; break
            }
        }
        Save-Config $cfg
    }
    Start-Sleep 1
}

function Remove-Instance {
    $cfg = Load-Config; Write-Host ""
    $custom = $cfg.instances | Where { -not $_.builtin }
    if (-not $custom) { Write-Host "  无可删除实例" -Fore DarkYellow; Start-Sleep 1; return }
    foreach ($i in $custom) {
        $n = if ($i.nick) { " ($($i.nick))" } else { '' }
        Write-Host "  [$($i.id)] $($i.name)$n" -Fore White
    }
    Write-Host ""
    $id = Read-Host "  删除编号(回车取消)"
    if ($id -and $id -match '^\d+$') {
        $t = $cfg.instances | Where { $_.id -eq [int]$id -and -not $_.builtin }
        if ($t -and (Read-Host "  确认删除 $($t.name)? (y/N)") -eq 'y') {
            Get-CimInstance Win32_Process -Filter "Name='douyinim.exe'" -EA SilentlyContinue |
                Where { $_.CommandLine -match [regex]::Escape($t.dir) } |
                ForEach { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
            Remove-Item (Join-Path $base $t.dir) -Recurse -Force -EA SilentlyContinue
            Remove-Item (Join-Path $env:APPDATA $t.datadir) -Recurse -Force -EA SilentlyContinue
            $cfg.instances = @($cfg.instances | Where { $_.id -ne [int]$id }); Save-Config $cfg
            Write-Host "  已删除" -Fore Red
        }
    }
    Start-Sleep 1
}

# ============ 主循环 (仅直接执行时启动) ============
if ($MyInvocation.InvocationName -ne '.') {
    while ($true) {
        Clear-Host
        Show-Dashboard
        Show-Menu
        $key = Read-Host "  请输入(回车刷新)"
        $k = "$key".ToLower()
        if (-not $k) { continue }
        switch -Regex ($k) {
            '^m$' { Start-Instance '' }
            '^(\d+)$' {
                $t = Get-InstanceByIndex ([int]$k)
                if ($t) { Start-Instance $t.dir }
                else { Write-Host "  无效" -Fore Red; Start-Sleep 1 }
            }
            '^a$' {
                Write-Host "  全部启动(间隔15秒)..." -Fore Cyan; Start-Instance ''
                $cfg = Load-Config
                foreach ($i in $cfg.instances) { if (-not $i.builtin) { Start-Sleep 15; Start-Instance $i.dir } }
                Write-Host "  完成!" -Fore Green; Start-Sleep 2
            }
            '^n$' { New-Instance }
            '^e$' { Edit-Nick }
            '^d$' { Remove-Instance }
            '^s$' {
                Write-Host "  安全关闭所有实例..." -Fore Yellow
                $douyin = Get-Process douyinim -EA SilentlyContinue
                if (-not $douyin) { Write-Host "  没有运行中的实例" -Fore DarkGray; Start-Sleep 1; continue }
                $douyin | ForEach-Object { $_.CloseMainWindow() | Out-Null }
                $waited = 0
                while ($waited -lt 20) {
                    Start-Sleep 2; $waited += 2
                    $left = Get-Process douyinim -EA SilentlyContinue
                    if (-not $left) { Write-Host "  全部已安全关闭 (${waited}秒)" -Fore Green; break }
                }
                $left = Get-Process douyinim -EA SilentlyContinue
                if ($left) {
                    Write-Host "  $($left.Count)个实例未响应，已跳过(不强杀)" -Fore Yellow
                    Write-Host "  请手动逐个关闭客户端窗口" -Fore Yellow
                }
                Start-Sleep 1
            }
            '^r$' { continue }
            '^q$' { exit }
        }
    }
}
