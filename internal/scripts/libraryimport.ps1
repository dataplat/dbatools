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

    $shared = @()
    # New SQL Auth types require newer versions of .NET, check
    # https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
    if ($psVersionTable.Platform -ne 'Unix') {
        if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -ge 461808 -and $PSVersionTable.PSEdition -ne 'Core' -and $host.Name -ne 'Visual Studio Code Host') {
            Write-Verbose -Message "Adding Azure DLLs"
            $shared += 'Microsoft.IdentityModel.Clients.ActiveDirectory', 'Microsoft.Azure.Services.AppAuthentication'
        }
    }

    $separator = [IO.Path]::DirectorySeparatorChar
    $shared += "third-party" + $separator + "Bogus" + $separator + "Bogus"

    foreach ($name in $shared) {
        $assemblyPath = "$script:PSModuleRoot" + $separator + "bin\libraries" + $separator + "$name.dll"

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

    foreach ($name in $names) {
        $x64only = 'Microsoft.SqlServer.Replication', 'Microsoft.SqlServer.XEvent.Linq', 'Microsoft.SqlServer.BatchParser', 'Microsoft.SqlServer.Rmo', 'Microsoft.SqlServer.BatchParserClient'
        if ($name -in $x64only -and $env:PROCESSOR_ARCHITECTURE -eq "x86") {
            Write-Verbose -Message "Skipping $name. x86 not supported for this library."
            continue
        }
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
if ($psVersionTable.Platform -ne 'Unix' -and $PSVersionTable.PSEdition -ne "Core" -and $host.Name -ne 'Visual Studio Code Host') {
    if ((Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -ge 461808) {
        Write-Verbose -Message "Loading app.config"
        # avoid issues with app.config file and VS Integrated Console
        $appconfig = "$(Get-DbatoolsConfigValue -FullName path.dbatoolstemp)\app.config"
        if (-not (Test-Path -Path $appconfig)) {
            $appconfigtext = '<?xml version="1.0" encoding="utf-8" ?>
<configuration>
	<configSections>
	   <!-- Change #1: Register the new SqlAuthenticationProvider configuration section -->
	   <section name="SqlAuthenticationProviders" type="System.Data.SqlClient.SqlAuthenticationProviderConfigurationSection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" />
	</configSections>
	<!-- Change #3: Add the new SqlAuthenticationProvider configuration section, registering the built-in authentication provider in AppAuth library -->
	<SqlAuthenticationProviders>
	   <providers>
		 <add name="Active Directory Interactive" type="Microsoft.Azure.Services.AppAuthentication.SqlAppAuthenticationProvider, Microsoft.Azure.Services.AppAuthentication" />
	   </providers>
	</SqlAuthenticationProviders>
</configuration>'
            $null = Set-Content -Path $appconfig -Value $appconfigtext -Encoding UTF8
        }
        # Load app.config that supports MFA
        [appdomain]::CurrentDomain.SetData("APP_CONFIG_FILE", $appconfig)
        Add-Type -AssemblyName System.Configuration
        # Clear some cache to make sure it loads
        [Configuration.ConfigurationManager].GetField("s_initState", "NonPublic, Static").SetValue($null, 0)
        [Configuration.ConfigurationManager].GetField("s_configSystem", "NonPublic, Static").SetValue($null, $null)
        ([Configuration.ConfigurationManager].Assembly.GetTypes() | Where-Object { $_.FullName -eq "System.Configuration.ClientConfigPaths" })[0].GetField("s_current", "NonPublic, Static").SetValue($null, $null)
    }
}