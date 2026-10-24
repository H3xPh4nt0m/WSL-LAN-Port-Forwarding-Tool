
#requires -RunAsAdministrator

# ==========================================
# CONFIGURATION — EDIT THESE VALUES
# ==========================================

$WindowsListenIP   = "192.168.1.3"
$WindowsListenPort = 20128

$WslTargetIP        = "172.31.168.53"
$WslTargetPort      = 20128

# Firewall rule names used by our previous scripts
$FirewallRuleNames = @(
    "WSL-LAN-Port-$WindowsListenPort",
    "WSL Server $WindowsListenPort LAN"
)

# ==========================================
# FIND AND REMOVE THE EXACT PORT FORWARD
# ==========================================

Write-Host "`nChecking port-forwarding rules..." -ForegroundColor Cyan

$RawRules = & netsh.exe interface portproxy show v4tov4

if ($LASTEXITCODE -ne 0) {
    throw "Could not read portproxy rules. No changes made."
}

$Rules = @(
    foreach ($Line in $RawRules) {
        if ($Line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s*$') {
            [PSCustomObject]@{
                ListenIP   = $Matches[1]
                ListenPort = [int]$Matches[2]
                TargetIP   = $Matches[3]
                TargetPort = [int]$Matches[4]
            }
        }
    }
)

# Fail safely if the output contains IP addresses
# but the forwarding table could not be parsed.
$RawText = $RawRules -join "`n"

if ($Rules.Count -eq 0 -and
    $RawText -match '\b(?:\d{1,3}\.){3}\d{1,3}\b') {
    throw "Could not parse the forwarding table. No changes made."
}

$SameListener = @(
    $Rules | Where-Object {
        $_.ListenIP -eq $WindowsListenIP -and
        $_.ListenPort -eq $WindowsListenPort
    }
)

if ($SameListener.Count -gt 0) {

    $ExactRule = @(
        $SameListener | Where-Object {
            $_.TargetIP -eq $WslTargetIP -and
            $_.TargetPort -eq $WslTargetPort
        }
    )

    if ($ExactRule.Count -eq 0) {
        $CurrentRule = $SameListener[0]

        Write-Warning (
            "The listening address exists, but its target is {0}:{1}, not {2}:{3}. No changes made." -f
            $CurrentRule.TargetIP,
            $CurrentRule.TargetPort,
            $WslTargetIP,
            $WslTargetPort
        )

        exit 1
    }

    Write-Host (
        "Removing {0}:{1} -> {2}:{3}" -f
        $WindowsListenIP,
        $WindowsListenPort,
        $WslTargetIP,
        $WslTargetPort
    ) -ForegroundColor Yellow

    & netsh.exe interface portproxy delete v4tov4 `
        "listenaddress=$WindowsListenIP" `
        "listenport=$WindowsListenPort"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove port forwarding."
    }

    Write-Host "Port forwarding removed." -ForegroundColor Green
}
else {
    Write-Host "No matching port-forwarding entry found." -ForegroundColor DarkYellow
}

# ==========================================
# REMOVE FIREWALL RULES CREATED BY OUR SCRIPTS
# ==========================================

Write-Host "`nChecking related Windows Firewall rules..." -ForegroundColor Cyan

foreach ($RuleName in $FirewallRuleNames) {

    $FirewallRules = @(
        Get-NetFirewallRule -DisplayName $RuleName `
            -ErrorAction SilentlyContinue
    )

    foreach ($FirewallRule in $FirewallRules) {
        Remove-NetFirewallRule -InputObject $FirewallRule -ErrorAction Stop

        Write-Host "Removed firewall rule: $RuleName" -ForegroundColor Green
    }
}

Write-Host "`nCleanup complete." -ForegroundColor Green
Write-Host "Check remaining forwarding rules with:"
Write-Host "netsh interface portproxy show v4tov4"
