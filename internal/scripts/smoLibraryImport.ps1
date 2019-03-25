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
            'Microsoft.SqlServer.SqlEnum',
            'System.Security.SecureString',
            'Microsoft.Data.Tools.Schema.Sql',
            'Microsoft.Data.Tools.Utilities',
            'Microsoft.SqlServer.Dac',
            'Microsoft.SqlServer.Dac.Extensions',
            'Microsoft.SqlServer.TransactSql.ScriptDom',
            'Microsoft.SqlServer.Types',
            'Microsoft.SqlServer.Management.RegisteredServers',
            'Microsoft.SqlTools.Hosting',
            'Microsoft.SqlTools.ManagedBatchParser'
        )
    } else {
        $names = @(
            'Microsoft.SqlServer.Smo',
            'Microsoft.SqlServer.Dmf',
            'Microsoft.SqlServer.SqlWmiManagement',
            'Microsoft.SqlServer.ConnectionInfo',
            'Microsoft.SqlServer.SmoExtended',
            'Microsoft.SqlServer.Management.RegisteredServers',
            'Microsoft.SqlServer.Management.Sdk.Sfc',
            'Microsoft.SqlServer.SqlEnum',
            'Microsoft.SqlServer.RegSvrEnum',
            'Microsoft.SqlServer.WmiEnum',
            'Microsoft.SqlServer.ServiceBrokerEnum',
            'Microsoft.SqlServer.Management.Collector',
            'Microsoft.SqlServer.Management.CollectorEnum',
            'Microsoft.SqlServer.Management.Utility',
            'Microsoft.SqlServer.Management.UtilityEnum',
            'Microsoft.SqlServer.Management.HadrDMF',
            'Microsoft.SqlServer.VulnerabilityAssessment.Model',
            'Microsoft.SqlServer.BatchParser',
            'Microsoft.SqlServer.BatchParserClient',
            'Microsoft.SqlServer.BulkInsertTaskConnections',
            'Microsoft.SqlServer.DtsServer.Interop',
            'Microsoft.SqlServer.Replication',
            'Microsoft.SqlServer.XE.Core',
            'Microsoft.SqlServer.XEvent.Configuration',
            'Microsoft.SqlServer.XEvent',
            'Microsoft.SqlServer.XEvent.Linq',
            'Microsoft.SqlServer.Rmo',
            'Accessibility',
            'Microsoft.AnalysisServices.AppLocal.Core',
            'Microsoft.AnalysisServices.AppLocal',
            'Microsoft.Azure.KeyVault.Core',
            'Microsoft.Data.Edm',
            'Microsoft.Data.OData',
            'Microsoft.Practices.TransientFaultHandling.Core',
            'Microsoft.DataTransfer.Common.Utils',
            'Microsoft.SqlServer.ConnectionInfoExtended',
            'Microsoft.SqlServer.Diagnostics.STrace',
            'Microsoft.SqlServer.Dmf.Common',
            'Microsoft.Build.Utilities.Core',
            'Microsoft.Build.Framework',
            'System.Collections.Immutable',
            'Microsoft.Data.Tools.Schema.Tasks.Sql',
            'Microsoft.SqlServer.TransactSql',
            'Microsoft.Data.Tools.Schema.Sql',
            'Microsoft.SqlServer.IntegrationServices.ClusterManagement',
            'Microsoft.SqlServer.IntegrationServices.ISServerDBUpgrade',
            'Microsoft.SqlServer.IntegrationServices.Server.Common',
            'Microsoft.SqlServer.IntegrationServices.Server',
            'Microsoft.SqlServer.IntegrationServices.Server.IPC',
            'Microsoft.SqlServer.IntegrationServices.server.shared',
            'Microsoft.SqlServer.IntegrationServices.TaskScheduler',
            'Microsoft.SqlServer.Management.IntegrationServices',
            'Microsoft.SqlServer.Management.IntegrationServicesEnum',
            'Microsoft.SqlServer.Management.Sdk.Scripting',
            'Microsoft.SqlServer.Management.SmartAdminPolicies',
            'Microsoft.SqlServer.Management.XEvent',
            'Microsoft.SqlServer.Management.XEventDbScoped',
            'Microsoft.SqlServer.Management.XEventDbScopedEnum',
            'Microsoft.SqlServer.Management.XEventEnum',
            'Microsoft.SqlServer.PolicyEnum',
            'Microsoft.SqlServer.Replication.BusinessLogicSupport',
            'Microsoft.SqlServer.SqlClrProvider',
            'Microsoft.SqlServer.SqlTDiagm',
            'Microsoft.SqlServer.SString',
            'Microsoft.SqlServer.DmfSqlClrWrapper',
            'Microsoft.SqlServer.Dac',
            'Microsoft.SqlServer.Dac.Extensions'
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