<#
.SYNOPSIS
    One-stop debugging helper for runner fleet instances -- no portal, no RDP required.

.DESCRIPTION
    Everything goes through the Azure guest agent, so it works with the default-deny
    NSG. Actions:

      list        - fleet instances with power state, age, and registered runners
      tail-runner - last lines of the newest runner diagnostic log on an instance
      tail-sql    - last lines of each SQL ERRORLOG on an instance
      processes   - top CPU processes on an instance
      screenshot  - boot-diagnostics screenshot URL (boot hangs)
      run         - run an arbitrary PowerShell snippet on an instance
      open-rdp    - TEMPORARY allow rule for RDP from your current public IP
      close-rdp   - remove that rule (also happens naturally: instances are disposable)
      delete      - delete a stuck instance (reconcile replaces it within 10 minutes)

.EXAMPLE
    ./debug.ps1 -Action list

.EXAMPLE
    ./debug.ps1 -Action tail-runner -InstanceName dbatools-runners_a1b2c3

.EXAMPLE
    ./debug.ps1 -Action run -InstanceName dbatools-runners_a1b2c3 -Script "Get-Service MSSQL*"

.NOTES
    Author: the dbatools team + Claude
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("list", "tail-runner", "tail-sql", "processes", "screenshot", "run", "open-rdp", "close-rdp", "delete")]
    [string]$Action,
    [string]$InstanceName,
    [string]$Script,
    [string]$ResourceGroup = "dbatools-ci",
    [string]$NsgName = "dbatools-ci-nsg",
    [string]$Repo = "dataplat/dbatools"
)

$ErrorActionPreference = "Stop"

function Invoke-FleetCommand {
    param(
        [string]$VmName,
        [string]$CommandText
    )
    az vm run-command invoke --resource-group $ResourceGroup --name $VmName --command-id RunPowerShellScript --scripts $CommandText --query "value[0].message" --output tsv --only-show-errors
}

switch ($Action) {
    "list" {
        az vm list --resource-group $ResourceGroup --show-details --query "[].{name: name, power: powerState, created: timeCreated, ip: publicIps}" --output table --only-show-errors
        Write-Host ""
        gh api "repos/$Repo/actions/runners?per_page=100" --jq ".runners[] | .name + \"  \" + .status + \"  busy=\" + (.busy | tostring)"
    }
    "tail-runner" {
        Invoke-FleetCommand -VmName $InstanceName -CommandText "Get-ChildItem C:\github-runner\_diag\*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Get-Content -Path (`$_.FullName) -Tail 40 }"
    }
    "tail-sql" {
        Invoke-FleetCommand -VmName $InstanceName -CommandText "Get-ChildItem -Path (`"C:\Program Files\Microsoft SQL Server\MSSQL*\MSSQL\Log\ERRORLOG`") | ForEach-Object { `"=== `" + `$_.FullName; Get-Content -Path (`$_.FullName) -Tail 15 }"
    }
    "processes" {
        Invoke-FleetCommand -VmName $InstanceName -CommandText "Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 Name, Id, CPU, WorkingSet | Format-Table | Out-String"
    }
    "screenshot" {
        az vm boot-diagnostics get-boot-log-uris --resource-group $ResourceGroup --name $InstanceName --output table --only-show-errors
    }
    "run" {
        if (-not $Script) {
            throw "-Script is required with -Action run"
        }
        Invoke-FleetCommand -VmName $InstanceName -CommandText $Script
    }
    "open-rdp" {
        $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org")
        $splatRule = @(
            "network", "nsg", "rule", "create",
            "--resource-group", $ResourceGroup,
            "--nsg-name", $NsgName,
            "--name", "temp-rdp",
            "--priority", "100",
            "--direction", "Inbound",
            "--access", "Allow",
            "--protocol", "Tcp",
            "--destination-port-ranges", "3389",
            "--source-address-prefixes", "$myIp/32",
            "--output", "none"
        )
        az @splatRule --only-show-errors
        Write-Host "RDP open from $myIp -- run ./debug.ps1 -Action close-rdp when done"
    }
    "close-rdp" {
        az network nsg rule delete --resource-group $ResourceGroup --nsg-name $NsgName --name "temp-rdp" --only-show-errors
        Write-Host "RDP rule removed"
    }
    "delete" {
        az vm delete --resource-group $ResourceGroup --name $InstanceName --yes --no-wait --only-show-errors
        Write-Host "$InstanceName deleting; reconcile will replace it if the floor requires"
    }
}
