# ==========================================
# AUDITORIA COMPLETA DE SAUDE DA MAQUINA
# ==========================================

# -------- Elevar para administrador --------
if (-not ([Security.Principal.WindowsPrincipal] `
[Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
[Security.Principal.WindowsBuiltInRole] "Administrator"))
{
Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
exit
}

# -------- Pasta do relatório --------
$Folder="C:\Temp\Relatorio_Maquina"

if(!(Test-Path $Folder)){
New-Item -ItemType Directory -Path $Folder | Out-Null
}

$Path="$Folder\Relatorio_$env:COMPUTERNAME.html"

# -------- Informações da máquina --------
$Computer = Get-CimInstance Win32_ComputerSystem
$BIOS = Get-CimInstance Win32_BIOS
$CPU = Get-CimInstance Win32_Processor
$RAM = Get-CimInstance Win32_OperatingSystem

# -------- Discos --------
$LogicalDisk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$PhysicalDisk = Get-PhysicalDisk

$DiskInfo = foreach ($d in $LogicalDisk){

$free = [math]::Round($d.FreeSpace/1GB,2)
$total = [math]::Round($d.Size/1GB,2)
$percent = [math]::Round(($free/$total)*100,2)

[PSCustomObject]@{
Drive = $d.DeviceID
LivreGB = $free
TotalGB = $total
LivrePercent = $percent
}
}

# -------- Tipo do disco --------
$DiskType = ($PhysicalDisk | Select MediaType -Unique).MediaType

# -------- SMART SSD --------
$SmartStatus="Desconhecido"

try{
$Smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus
if($Smart.PredictFailure){
$SmartStatus="ALERTA"
}else{
$SmartStatus="Saudavel"
}
}catch{
$SmartStatus="Nao suportado"
}

# -------- Temperatura CPU --------
$TempCPU="Nao disponivel"

try{
$temp = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi"
$TempCPU = [math]::Round(($temp.CurrentTemperature - 2732) / 10,1)
}catch{}

# -------- BitLocker --------
$Bitlocker="Nao suportado"

try{
$BitlockerInfo = Get-BitLockerVolume
if($BitlockerInfo.ProtectionStatus -eq "On"){
$Bitlocker="Ativo"
}else{
$Bitlocker="Desativado"
}
}catch{}

# -------- Defender --------
$DefenderStatus="Nao detectado"

try{
$Defender = Get-MpComputerStatus
if($Defender.AntivirusEnabled){
$DefenderStatus="Ativo"
}else{
$DefenderStatus="Desativado"
}
}catch{}

# -------- Windows Update --------
$UpdatesPendentes = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count

# -------- Inventário de softwares --------
$SoftwareList = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
Where-Object {$_.DisplayName} |
Select DisplayName,DisplayVersion

# -------- Verificar atualizações via Winget --------
$SoftwaresStatus = @()
$Score = 100

try{

$WingetUpgrade = winget upgrade --accept-source-agreements 2>$null

foreach ($sw in $SoftwareList){

$status="Atualizado"

if($WingetUpgrade -match $sw.DisplayName){
$status="Desatualizado"
$Score -= 1
}

$SoftwaresStatus += [PSCustomObject]@{
Nome=$sw.DisplayName
Versao=$sw.DisplayVersion
Status=$status
}

}

}catch{

foreach ($sw in $SoftwareList){

$SoftwaresStatus += [PSCustomObject]@{
Nome=$sw.DisplayName
Versao=$sw.DisplayVersion
Status="Desconhecido"
}

}

}

# -------- Score disco --------
foreach($d in $DiskInfo){
if($d.LivrePercent -lt 15){
$Score -= 20
}
}

if($SmartStatus -eq "ALERTA"){
$Score -= 40
}

if($UpdatesPendentes -gt 10){
$Score -= 10
}

# -------- Cor do Score --------
$ScoreColor="green"

if($Score -lt 80){$ScoreColor="orange"}
if($Score -lt 60){$ScoreColor="red"}

# -------- HTML --------
$HTML = @"

<html>

<head>

<title>Relatorio de Saude</title>

<style>

body{font-family:Segoe UI;background:#f4f6f8}

.card{
background:white;
padding:20px;
margin:20px;
border-radius:10px;
box-shadow:0 0 6px #ccc
}

.score{
font-size:50px;
color:$ScoreColor
}

table{
border-collapse:collapse;
width:100%
}

td,th{
border:1px solid #ddd;
padding:8px
}

th{
background:#333;
color:white
}

</style>

</head>

<body>

<div class='card'>
<h1>Relatorio de Saude da Maquina</h1>

<p><b>Computador:</b> $env:COMPUTERNAME</p>
<p><b>Modelo:</b> $($Computer.Model)</p>
<p><b>Serial:</b> $($BIOS.SerialNumber)</p>
<p><b>BIOS:</b> $($BIOS.SMBIOSBIOSVersion)</p>
</div>

<div class='card'>
<h2>Score de Saude</h2>
<div class='score'>$Score</div>
</div>

<div class='card'>
<h2>CPU</h2>
<p>$($CPU.Name)</p>
<p>Temperatura: $TempCPU °C</p>
</div>

<div class='card'>
<h2>Memoria</h2>
<p>Total RAM: $([math]::Round($RAM.TotalVisibleMemorySize/1MB,2)) GB</p>
</div>

<div class='card'>
<h2>Discos</h2>

<table>
<tr>
<th>Drive</th>
<th>Total GB</th>
<th>Livre GB</th>
<th>Livre %</th>
</tr>

$(foreach($d in $DiskInfo){
"<tr><td>$($d.Drive)</td><td>$($d.TotalGB)</td><td>$($d.LivreGB)</td><td>$($d.LivrePercent)%</td></tr>"
})

</table>

<p>Tipo de Disco: $DiskType</p>
<p>SMART SSD: $SmartStatus</p>

</div>

<div class='card'>
<h2>Seguranca</h2>
<p>BitLocker: $Bitlocker</p>
<p>Defender: $DefenderStatus</p>
</div>

<div class='card'>
<h2>Atualizacoes</h2>
<p>Windows Updates pendentes: $UpdatesPendentes</p>
</div>

<div class='card'>

<h2>Softwares Instalados</h2>

<table>

<tr>
<th>Software</th>
<th>Versao</th>
<th>Status</th>
</tr>

$(foreach($s in $SoftwaresStatus){

$color="green"
if($s.Status -eq "Desatualizado"){ $color="red" }
if($s.Status -eq "Desconhecido"){ $color="orange" }

"<tr>
<td>$($s.Nome)</td>
<td>$($s.Versao)</td>
<td style='color:$color'>$($s.Status)</td>
</tr>"

})

</table>

</div>

</body>

</html>

"@

# -------- Salvar relatório --------
$HTML | Out-File $Path -Encoding UTF8

# -------- Abrir relatório --------
Start-Process $Path