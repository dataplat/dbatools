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
        if (-not $DoCopy) {
            return
        }

        $DllRoot = (Resolve-Path -Path $DllRoot)

        if ((Resolve-Path -Path "$ModuleRoot\bin\smo") -eq $DllRoot) {
            return
        }

        if (-not (Test-Path $DllRoot)) {
            $null = New-Item -Path $DllRoot -ItemType Directory -ErrorAction Ignore
        }

        Copy-Item -Path "$ModuleRoot\bin\smo\$Name.dll" -Destination $DllRoot
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
            'Bogus',
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
            'Microsoft.SqlServer.XEvent.Linq',
            'Microsoft.SqlServer.Replication',
            'Microsoft.SqlServer.Rmo'
        )
    }
    #endregion Names

    $basePath = $dllRoot
    if ($PSVersionTable.PSEdition -eq 'core') {
        $basePath = "$(Join-Path $dllRoot coreclr)"
    }

    # New SQL Auth types require newer versions of .NET, check
    # https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
    if ($psVersionTable.Platform -ne 'Unix') {
        if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -ge 461808 -and $PSVersionTable.PSEdition -ne "Core") {
            Write-Verbose -Message "Adding Azure DLLs"
            $names += 'Microsoft.IdentityModel.Clients.ActiveDirectory', 'Microsoft.Azure.Services.AppAuthentication'
        }
    } else {
        $shared = "bogus"
        foreach ($name in $shared) {
            $assemblyPath = "$dllRoot([IO.Path]::DirectorySeparatorChar)$name.dll"
            $null = try {
                Import-Module $assemblyPath
            } catch {
                try {
                    [Reflection.Assembly]::LoadFrom($assemblyPath)
                } catch {
                    Write-Error "Could not import $assemblyPath : $($_ | Out-String)"
                }
            }
        }
    }

    foreach ($name in $names) {
        Copy-Assembly -ModuleRoot $ModuleRoot -DllRoot $DllRoot -DoCopy $DoCopy -Name $name
        $assemblyPath = "$basepath$([IO.Path]::DirectorySeparatorChar)$name.dll"
        $null = try {
            Import-Module $assemblyPath
        } catch {
            try {
                [Reflection.Assembly]::LoadFrom($assemblyPath)
            } catch {
                Write-Error "Could not import $assemblyPath : $($_ | Out-String)"
            }
        }
    }
}

$script:serialImport = $true
if ($script:serialImport) {
    $scriptBlock.Invoke($script:PSModuleRoot, "$(Join-Path $script:DllRoot smo)", $script:copyDllMode)
} else {
    $script:smoRunspace = [System.Management.Automation.PowerShell]::Create()
    if ($script:smoRunspace.Runspace.Name) {
        try { $script:smoRunspace.Runspace.Name = "dbatools-import-smo" }
        catch { }
    }
    $script:smoRunspace.AddScript($scriptBlock).AddArgument($script:PSModuleRoot).AddArgument("$(Join-Path $script:DllRoot smo)").AddArgument((-not $script:strictSecurityMode))
    $script:smoRunspace.BeginInvoke()
}

# if .net 4.7.2 load new sql auth config
if ($psVersionTable.Platform -ne 'Unix') {
    if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -ge 461808 -and $PSVersionTable.PSEdition -ne "Core") {
        Write-Verbose -Message "Loading app.config"
        # Load app.config that supports MFA
        $configpath = "$script:PSModuleRoot\bin\app.config"
        [appdomain]::CurrentDomain.SetData("APP_CONFIG_FILE", $configpath)
        Add-Type -AssemblyName System.Configuration
        # Clear some cache to make sure it loads
        [Configuration.ConfigurationManager].GetField("s_initState", "NonPublic, Static").SetValue($null, 0)
        [Configuration.ConfigurationManager].GetField("s_configSystem", "NonPublic, Static").SetValue($null, $null)
        ([Configuration.ConfigurationManager].Assembly.GetTypes() | Where-Object {$_.FullName -eq "System.Configuration.ClientConfigPaths"})[0].GetField("s_current", "NonPublic, Static").SetValue($null, $null)
    }
}