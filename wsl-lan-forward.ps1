#requires -RunAsAdministrator

# ==========================================
# CONFIGURATION — EDIT THESE VALUES
# ==========================================

$WindowsListenIP    = "192.168.1.3"
$WindowsListenPort  = 20128

$WslDistro          = "Ubuntu-24.04"
$WslConnectPort     = 20128

$AllowedRemoteSubnet = "192.168.1.0/24"
$FirewallRuleName    = "WSL-LAN-Port-$WindowsListenPort"

# ==========================================
# CHECK WINDOWS NETWORK ADDRESS
# ==========================================

Write-Host "`n[1/5] Checking Windows host IP..." -ForegroundColor Cyan

if (-not (Get-NetIPAddress -IPAddress $WindowsListenIP `
    -ErrorAction SilentlyContinue)) {
    throw "Windows IP $WindowsListenIP is not assigned to this machine."
}

# ==========================================
# DETECT CURRENT WSL IP AUTOMATICALLY
# ==========================================

Write-Host "[2/5] Detecting Ubuntu WSL IP..." -ForegroundColor Cyan

$WslOutput = & wsl.exe -d $WslDistro -- hostname -I 2>$null

if ($LASTEXITCODE -ne 0) {
    throw "Could not access WSL distro '$WslDistro'. Check the name using: wsl -l -q"
}

$WslIP = (
    ($WslOutput -join " ").Trim() -split "\s+" |
    Where-Object {
        $_ -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and
        $_ -ne "127.0.0.1"
    } |
    Select-Object -First 1
)

if (-not $WslIP) {
    throw "Could not detect the WSL IPv4 address."
}

Write-Host "Detected WSL IP: $WslIP" -ForegroundColor Green

# ==========================================
# ENSURE IP HELPER SERVICE IS RUNNING
# ==========================================

Write-Host "[3/5] Checking IP Helper service..." -ForegroundColor Cyan

$IpHelper = Get-Service -Name iphlpsvc -ErrorAction Stop

if ($IpHelper.Status -ne "Running") {
    Start-Service -Name iphlpsvc
}

# ==========================================
# CONFIGURE PORT FORWARDING
# ==========================================

Write-Host "[4/5] Configuring port forwarding..." -ForegroundColor Cyan

# Remove the previous rule if it exists.
& netsh.exe interface portproxy delete v4tov4 `
    "listenaddress=$WindowsListenIP" `
    "listenport=$WindowsListenPort" 2>$null | Out-Null

# Add the updated rule.
& netsh.exe interface portproxy add v4tov4 `
    "listenaddress=$WindowsListenIP" `
    "listenport=$WindowsListenPort" `
    "connectaddress=$WslIP" `
    "connectport=$WslConnectPort"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure port forwarding."
}

# ==========================================
# CONFIGURE WINDOWS FIREWALL
# ==========================================

Write-Host "[5/5] Configuring Windows Firewall..." -ForegroundColor Cyan

Get-NetFirewallRule -DisplayName $FirewallRuleName `
    -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

New-NetFirewallRule `
    -DisplayName $FirewallRuleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalAddress $WindowsListenIP `
    -LocalPort $WindowsListenPort `
    -RemoteAddress $AllowedRemoteSubnet `
    -Profile Any | Out-Null

# ==========================================
# SUCCESS
# ==========================================

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " WSL SERVER PORT FORWARDING CONFIGURED" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

Write-Host "Windows IP : $WindowsListenIP"
Write-Host "Windows port: $WindowsListenPort"
Write-Host "WSL IP     : $WslIP"
Write-Host "WSL port   : $WslConnectPort"
Write-Host "LAN access : http://${WindowsListenIP}:$WindowsListenPort"

Write-Host "`nPort forwarding rules:" -ForegroundColor Cyan
netsh.exe interface portproxy show v4tov4