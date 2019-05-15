$scriptBlock = {
    param (
        $ModuleRoot,

        $DllRoot,

        $DoCopy
    )

    function Copy-Assembly {
        [CmdletBinding()]
        param (
            [string]$ModuleRoot,
            [string]$DllRoot,
            [bool]$DoCopy,
            [string]$Name
        )
        $DllRoot = (Resolve-Path -Path $DllRoot)

        if (-not $DoCopy) {
            return
        }
        if ((Resolve-Path -Path "$ModuleRoot\bin\smo") -eq $DllRoot) {
            return
        }

        if (-not (Test-Path $DllRoot)) {
            $null = New-Item -Path $DllRoot -ItemType Directory -ErrorAction Ignore
        }

        Copy-Item -Path (Resolve-Path -Path "$ModuleRoot\bin\smo\$Name.dll") -Destination $DllRoot
    }

    #region Names
    if ($PSVersionTable.PSEdition -eq "Core") {
        $names = @(
            'Microsoft.Data.Tools.Sql.BatchParser',
            'Microsoft.SqlServer.ConnectionInfo',
            'Microsoft.SqlServer.Management.Dmf',
            'Microsoft.SqlServer.Management.PSProvider',
            'Microsoft.SqlServer.Management.PSSnapins',
            'Microsoft.SqlServer.Management.Sdk.Sfc',
            'Microsoft.SqlServer.Management.XEvent',
            'Microsoft.SqlServer.Management.XEventDbScoped',
            'Microsoft.SqlServer.Management.XEventDbScopedEnum',
            'Microsoft.SqlServer.Management.XEventEnum',
            'Microsoft.SqlServer.Smo',
            'Microsoft.SqlServer.SmoExtended',
            'System.Security.SecureString',
            'Microsoft.Data.Tools.Utilities',
            'Microsoft.SqlServer.Dac',
            'Microsoft.SqlServer.Dac.Extensions',
            'Microsoft.SqlServer.Types',
            'Microsoft.SqlServer.Management.RegisteredServers',
            'Microsoft.SqlTools.Hosting',
            'Microsoft.SqlTools.ManagedBatchParser'
        )
    } else {
        $names = @(
            'Microsoft.SqlServer.Smo',
            'Microsoft.SqlServer.SmoExtended',
            'Microsoft.SqlServer.ConnectionInfo',
            'Microsoft.SqlServer.BatchParser',
            'Microsoft.SqlServer.BatchParserClient',
            'Microsoft.SqlServer.Management.XEvent',
            'Microsoft.SqlServer.Management.XEventDbScoped',
            'Microsoft.SqlServer.Management.Sdk.Sfc',
            'Microsoft.SqlServer.SqlWmiManagement',
            'Microsoft.SqlServer.Management.RegisteredServers',
            'Microsoft.SqlServer.Management.Collector',
            'Microsoft.SqlServer.ConnectionInfoExtended',
            'Microsoft.SqlServer.Management.IntegrationServices',
            'Microsoft.SqlServer.SqlClrProvider',
            'Microsoft.SqlServer.SqlTDiagm',
            'Microsoft.SqlServer.SString',
            'Microsoft.SqlServer.Dac',
            'Microsoft.Data.Tools.Sql.BatchParser',
            'Microsoft.Data.Tools.Utilities',
            'Microsoft.SqlServer.Dmf',
            'Microsoft.SqlServer.Dmf.Common',
            'Microsoft.SqlServer.Types',
            'Microsoft.SqlServer.XE.Core',
            'Microsoft.SqlServer.XEvent.Linq',
            'Microsoft.SqlServer.Replication',
            'Microsoft.SqlServer.Rmo'
        )
    }
    #endregion Names

    foreach ($name in $names) {
        Copy-Assembly -ModuleRoot $ModuleRoot -DllRoot $DllRoot -DoCopy $DoCopy -Name $name
    }
    if ($PSVersionTable.PSEdition -eq "Core") {
        foreach ($name in $names) {
            Add-Type -Path (Resolve-Path -Path "$DllRoot\coreclr\$name.dll")
        }
    } else {
        foreach ($name in $names) {
            try {
                Add-Type -Path (Resolve-Path -Path "$DllRoot\$name.dll") -ErrorAction Stop
            } catch {
                continue
            }
        }
    }
}

$smo = (Resolve-Path -Path "$script:DllRoot\smo")

if ($script:serialImport) {
    $scriptBlock.Invoke($script:PSModuleRoot, "$script:DllRoot\smo", $script:copyDllMode)
} else {
    $script:smoRunspace = [System.Management.Automation.PowerShell]::Create()
    if ($script:smoRunspace.Runspace.Name) {
        try { $script:smoRunspace.Runspace.Name = "dbatools-import-smo" }
        catch { }
    }
    $script:smoRunspace.AddScript($scriptBlock).AddArgument($script:PSModuleRoot).AddArgument($smo).AddArgument((-not $script:strictSecurityMode))
    $script:smoRunspace.BeginInvoke()
}