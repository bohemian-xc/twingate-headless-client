<#
.SYNOPSIS
    Dynamically manage Windows static routes for WSL2 instances.

.DESCRIPTION
    Reads route configuration from a JSON file (routes.json) located
    in the same directory as this script, retrieves each WSL2 instance’s
    IP, and either adds or deletes corresponding Windows routes.

.PARAMETER Mode
    'add'     -> Add or update routes (default)
    'delete'  -> Remove existing routes only
#>

param(
    [ValidateSet("add","delete")]
    [string]$Mode = "add",

    [string]$ConfigPath
)

# --- Determine JSON config path relative to this script ---
if (-not $ConfigPath) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $ConfigPath = Join-Path $ScriptDir "host-to-wsl.json"
}

# --- Load configuration ---
if (-not (Test-Path $ConfigPath)) {
    Write-Error "❌ Configuration file not found: $ConfigPath"
    exit 1
}

try {
    $routes = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "❌ Failed to parse JSON: $($_.Exception.Message)"
    exit 1
}

Write-Host "=== Running in '$Mode' mode using config: $ConfigPath ===`n"

foreach ($r in $routes) {
    $distro = $r.Distro
    $subnet = $r.Subnet
    $mask   = $r.Mask
    $metric = $r.Metric

    Write-Host "Processing route for subnet $subnet ($distro)..."

    # --- Always delete old route first ---
    route delete $subnet | Out-Null

    if ($Mode -eq "delete") {
        Write-Host "  🗑️  Route deleted for $subnet"
        continue
    }

    # --- Get current WSL2 IP ---
    try {
        # Start WSL instance silently if needed
        wsl -d $distro -- echo >$null

        $ipOutput = wsl -d $distro hostname -I 2>$null
        if (-not $ipOutput) {
            Write-Warning "⚠ No IP returned from '$distro'. Skipping..."
            continue
        }

        $wsl_ip = ($ipOutput -split '\s+' | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })[0]
        if (-not $wsl_ip) {
            Write-Warning "⚠ Could not parse IPv4 address from '$distro'."
            continue
        }

        Write-Host "  ✅ Found IP: $wsl_ip"
    }
    catch {
        Write-Warning "⚠ Failed to get IP for '$distro': $($_.Exception.Message)"
        continue
    }

    # --- Add new persistent route ---
    $cmd = "route -p add $subnet mask $mask $wsl_ip metric $metric"
    Write-Host "  ➕ Adding route: $cmd"
    try {
        iex $cmd | Out-Null
    } catch {
        Write-Warning "⚠ Failed to add route for $subnet"
    }

    Write-Host ""
}

Write-Host "`n=== Route operation '$Mode' completed ==="
