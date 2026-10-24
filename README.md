# WSL LAN Port Forwarding Tool

A small PowerShell utility for making a server running inside **Ubuntu on WSL 2** reachable from other devices on your local network. It uses Windows `netsh interface portproxy` to forward traffic from a Windows host IP and port to the current WSL IPv4 address, and adds a Windows Defender Firewall rule for the configured LAN subnet.

It includes two scripts:

- **`wsl-lan-forward.ps1`** — detects the current WSL IPv4 address and configures port forwarding and a firewall rule.
- **`remove-wsl-forward.ps1`** — removes a selected port-forwarding entry and the matching firewall rule names used by this tool.

> Use this only on systems and networks you own or are authorized to administer. Keep access limited to trusted LAN devices; do not expose development or administration servers directly to the public internet.

## Example

Suppose:

| Setting | Example value |
|---|---|
| Windows host IP | `192.168.1.3` |
| Other LAN device | `192.168.1.4` |
| WSL server port | `20128` |
| WSL IP | Detected automatically by the forward script |
| Allowed LAN subnet | `192.168.1.0/24` |

Once forwarding is configured, open this address from the other device:

```text
http://192.168.1.3:20128
```

Replace the example IP addresses, subnet, and port with the values for your network.

## Requirements

- Windows with PowerShell and WSL 2 installed.
- An Ubuntu WSL distribution (or another distribution name configured in the script).
- A server running inside WSL and listening on the configured port.
- Administrator privileges in Windows PowerShell to configure port forwarding and Windows Firewall.
- The Windows host and client device connected to the same trusted LAN, with LAN connectivity permitted by the network.

## 1. Configure the WSL server

The service inside WSL must listen on an address reachable through the WSL virtual network, normally `0.0.0.0`, rather than only `127.0.0.1`.

For example, a Python HTTP server on port `20128` can be started with:

```bash
python3 -m http.server 20128 --bind 0.0.0.0
```

Use the appropriate command for your application. Check the listening address and port with:

```bash
ss -lntp
```

## 2. Configure `wsl-lan-forward.ps1`

Edit the configuration block near the top of `wsl-lan-forward.ps1`:

```powershell
$WindowsListenIP     = "192.168.1.3"
$WindowsListenPort   = 20128

$WslDistro           = "Ubuntu"
$WslConnectPort      = 20128

$AllowedRemoteSubnet = "192.168.1.0/24"
$FirewallRuleName    = "WSL-LAN-Port-$WindowsListenPort"
```

What these variables mean:

- **`$WindowsListenIP`** — the Windows network interface address clients connect to.
- **`$WindowsListenPort`** — the port exposed on Windows.
- **`$WslDistro`** — the exact WSL distribution name, such as `Ubuntu` or `Ubuntu-24.04`. See available names with `wsl -l -q`.
- **`$WslConnectPort`** — the port your application listens on inside WSL. It can differ from the Windows listening port.
- **`$AllowedRemoteSubnet`** — source subnet permitted by the firewall rule. Set this to your actual trusted LAN subnet.

The script detects the current WSL IPv4 address automatically. It checks that the Windows listening IP is assigned to the host, ensures the Windows IP Helper service is running, creates the portproxy entry, and installs a TCP inbound firewall rule limited to the configured remote subnet.

## 3. Run the forwarding script

Open **PowerShell as Administrator**, change to the directory containing the script, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\wsl-lan-forward.ps1
```

The execution-policy setting applies only to that PowerShell process. It does not permanently change the machine's execution policy.

When the script completes, it prints the detected WSL IP and the Windows URL to use. From another device on the allowed LAN, open the printed URL in a browser. For the example above:

```text
http://192.168.1.3:20128
```

## 4. Remove a forwarding entry

Edit the configuration block at the top of `remove-wsl-forward.ps1` so it exactly identifies the forwarding entry you want to delete:

```powershell
$WindowsListenIP   = "192.168.1.3"
$WindowsListenPort = 20128

$WslTargetIP        = "172.31.168.53"
$WslTargetPort      = 20128
```

Use the **current target WSL IP** shown by `netsh interface portproxy show v4tov4`. The WSL IP may have changed since the forwarding rule was created. The removal script checks the listener and target before deleting the entry, helping avoid deleting a different forwarding rule that happens to use the same Windows address and port.

Then, in **PowerShell as Administrator**, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\remove-wsl-forward.ps1
```

The script removes the matching portproxy entry and firewall rules with the names used by the forwarding script. It does not stop the Windows IP Helper service or remove unrelated portproxy entries.

To inspect existing port-forwarding rules at any time:

```powershell
netsh interface portproxy show v4tov4
```

## Troubleshooting

### The other device cannot open the page

1. Confirm the server is running inside WSL and listening on the configured port:
   ```bash
   ss -lntp
   ```
2. Confirm it listens on `0.0.0.0`, not only `127.0.0.1`.
3. Run the forwarding script again in an elevated PowerShell window.
4. Check the configured rules:
   ```powershell
   netsh interface portproxy show v4tov4
   Get-NetFirewallRule -DisplayName "WSL-LAN-Port-20128"
   ```
5. Verify the Windows IP is still correct and that Windows identifies the LAN as a trusted/private network if your local security policy depends on that classification.
6. Check that client isolation, a guest Wi-Fi network, or another LAN policy is not blocking device-to-device traffic.

### It stopped working after WSL restarted

WSL's virtual IP address can change. Run `wsl-lan-forward.ps1` again; it redetects the current WSL IPv4 address and updates the forwarding entry.

### The WSL distribution name is different

Run:

```powershell
wsl -l -q
```

Copy the exact distribution name into `$WslDistro` in `wsl-lan-forward.ps1`.

## Security notes

- The firewall rule is limited to `$AllowedRemoteSubnet`, but that subnet must be chosen carefully. A broad or incorrect subnet can allow more devices than intended.
- The forward script binds to the specific Windows IP configured in `$WindowsListenIP`, not every host interface.
- This utility configures TCP forwarding; it does not configure UDP forwarding.
- Do not add router port-forwarding rules for this service unless you have deliberately designed and secured public access.
- Use an application server appropriate for your environment. Built-in development servers are usually intended for development, not production.
- Review the scripts before running them, especially when using an administrator shell.

## License

No license is specified by this repository yet. Add a `LICENSE` file before presenting the project as open source, and choose a license that matches your intentions.
