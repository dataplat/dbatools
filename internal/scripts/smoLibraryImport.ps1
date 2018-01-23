$scriptBlock = {
    Param (
        $ModuleRoot,

        $DllRoot,

        $DoCopy
    )

    function Copy-Assembly {
        [CmdletBinding()]
        Param (
            [string]$ModuleRoot,
            [string]$DllRoot,
            [bool]$DoCopy,
            [string]$Name
        )

        if (-not $DoCopy) {
            return
        }
        if ("$ModuleRoot\bin\smo" -eq $DllRoot) {
            return
        }

        if (-not (Test-Path $DllRoot)) {
            $null = New-Item -Path $DllRoot -ItemType Directory -ErrorAction Ignore
        }

        Copy-Item -Path "$ModuleRoot\bin\smo\$Name.dll" -Destination $DllRoot
    }

    #region Names
    $names = @(
        'Microsoft.SqlServer.BatchParser',
        'Microsoft.SqlServer.BatchParserClient',
        'Microsoft.SqlServer.BulkInsertTaskConnections',
        'Microsoft.SqlServer.DTSRuntimeWrap',
        'Microsoft.SqlServer.DtsServer.Interop',
        'Microsoft.SqlServer.DTSUtilities',
        'Microsoft.SqlServer.ForEachFileEnumeratorWrap',
        'Microsoft.SqlServer.ManagedDTS',
        'Microsoft.SqlServer.IntegrationServices.ODataConnectionManager',
        'Microsoft.SqlServer.IntegrationServices.ODataSrc',
        'Microsoft.SqlServer.PipelineHost',
        'Microsoft.SqlServer.PackageFormatUpdate',
        'Microsoft.SqlServer.Replication',
        'Microsoft.SqlServer.SqlCEDest',
        'Microsoft.SqlServer.SQLTask',
        'Microsoft.SqlServer.TxScript',
        'Microsoft.SqlServer.XE.Core',
        'Microsoft.SqlServer.XEvent.Configuration',
        'Microsoft.SqlServer.XEvent',
        'Microsoft.SqlServer.XEvent.Linq',
        'Microsoft.SqlServer.XmlSrc',
        'Microsoft.SqlServer.Rmo',
        'Microsoft.SqlServer.DTSPipelineWrap',
        'Microsoft.SqlServer.ScriptTask',

        'Accessibility',
        'EnvDTE',
        'Microsoft.AnalysisServices.AppLocal.Core',
        'Microsoft.AnalysisServices.AppLocal',
        'Microsoft.Azure.KeyVault.Core',
        'Microsoft.Data.Edm',
        'Microsoft.Data.OData',
        'Microsoft.Practices.TransientFaultHandling.Core',
        'Microsoft.DataTransfer.Common.Utils',
        'Microsoft.SqlServer.ASTasks',
        'Microsoft.SqlServer.ConnectionInfo',
        'Microsoft.SqlServer.ConnectionInfoExtended',
        'Microsoft.SqlServer.DataProfiler',
        'Microsoft.SqlServer.DataProfilingTask',
        'Microsoft.SqlServer.Diagnostics.STrace',
        'Microsoft.SqlServer.Dmf.Common',
        'Microsoft.SqlServer.Dmf',
        'Microsoft.SqlServer.DMQueryTask',
        'Microsoft.SqlServer.DTEnum',
        'Microsoft.SqlServer.Dts.Design',
        'Microsoft.SqlServer.Dts.DtsClient',
        'Microsoft.SqlServer.DtsMsg',
        'Microsoft.SqlServer.Edition',
        'Microsoft.SqlServer.ExecProcTask',
        'Microsoft.SqlServer.ExpressionTask',
        'Microsoft.SqlServer.FileSystemTask',
        'Microsoft.SqlServer.ForEachADOEnumerator',
        'Microsoft.SqlServer.ForEachFromVarEnumerator',
        'Microsoft.SqlServer.ForEachNodeListEnumerator',
        'Microsoft.SqlServer.ForEachSMOEnumerator',
        'Microsoft.SqlServer.FtpTask',
        'Microsoft.SqlServer.GridControl',
        'Microsoft.SqlServer.Instapi',
        'Microsoft.SqlServer.IntegrationServices.ClusterManagement',
        'Microsoft.SqlServer.IntegrationServices.Common.ObjectModel',
        'Microsoft.SqlServer.IntegrationServices.ISServerDBUpgrade',
        'Microsoft.SqlServer.IntegrationServices.Server.Common',
        'Microsoft.SqlServer.IntegrationServices.Server',
        'Microsoft.SqlServer.IntegrationServices.Server.IPC',
        'Microsoft.SqlServer.IntegrationServices.server.shared',
        'Microsoft.SqlServer.IntegrationServices.TaskScheduler',
        'Microsoft.SqlServer.ManagedConnections',
        'Microsoft.SqlServer.Management.Collector',
        'Microsoft.SqlServer.Management.CollectorEnum',
        'Microsoft.SqlServer.Management.CollectorTasks',
        'Microsoft.SqlServer.Management.HadrDMF',
        'Microsoft.SqlServer.Management.HelpViewer',
        'Microsoft.SqlServer.Management.IntegrationServices',
        'Microsoft.SqlServer.Management.IntegrationServicesEnum',
        'Microsoft.SqlServer.Management.RegisteredServers',
        'Microsoft.SqlServer.Management.Sdk.Sfc',
        'Microsoft.SqlServer.Management.SmartAdminPolicies',
        'Microsoft.SqlServer.Management.SqlParser',
        'Microsoft.SqlServer.Management.SystemMetadataProvider',
        'Microsoft.SqlServer.Management.Utility',
        'Microsoft.SqlServer.Management.UtilityEnum',
        'Microsoft.SqlServer.Management.XEvent',
        'Microsoft.SqlServer.Management.XEventDbScoped',
        'Microsoft.SqlServer.Management.XEventDbScopedEnum',
        'Microsoft.SqlServer.Management.XEventEnum',
        'Microsoft.SqlServer.MSMQTask',
        'Microsoft.SqlServer.PipelineXML',
        'Microsoft.SqlServer.PolicyEnum',
        'Microsoft.SqlServer.RegSvrEnum',
        'Microsoft.SqlServer.Replication.BusinessLogicSupport',
        'Microsoft.SqlServer.SendMailTask',
        'Microsoft.SqlServer.ServiceBrokerEnum',
        'Microsoft.SqlServer.Smo',
        'Microsoft.SqlServer.SmoExtended',
        'Microsoft.SqlServer.SqlClrProvider',
        'Microsoft.SqlServer.SqlEnum',
        'Microsoft.SqlServer.SQLTaskConnectionsWrap',
        'Microsoft.SqlServer.SqlTDiagm',
        'Microsoft.SqlServer.SqlWmiManagement',
        'Microsoft.SqlServer.SString',
        'Microsoft.SqlServer.TransferDatabasesTask',
        'Microsoft.SqlServer.TransferErrorMessagesTask',
        'Microsoft.SqlServer.TransferJobsTask',
        'Microsoft.SqlServer.TransferLoginsTask',
        'Microsoft.SqlServer.TransferObjectsTask',
        'Microsoft.SqlServer.TransferSqlServerObjectsTask',
        'Microsoft.SqlServer.TransferStoredProceduresTask',
        'Microsoft.SqlServer.Types',
        'Microsoft.SqlServer.Types.resources',
        'Microsoft.SqlServer.VSTAScriptingLib',
        'Microsoft.SqlServer.WebServiceTask',
        'Microsoft.SqlServer.WMIDRTask',
        'Microsoft.SqlServer.WmiEnum',
        'Microsoft.SqlServer.WMIEWTask',
        'Microsoft.SqlServer.XMLTask',

        'Microsoft.SqlServer.Dmf.Adapters',
        'Microsoft.SqlServer.DmfSqlClrWrapper'
    )
    #endregion Names

    foreach ($name in $names) {
        Copy-Assembly -ModuleRoot $ModuleRoot -DllRoot $DllRoot -DoCopy $DoCopy -Name $name
    }
    foreach ($name in $names) {
        Add-Type -Path "$DllRoot\$name.dll"
    }

    <#
Likely don't need yet
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.WizardFramework.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.WizardFrameworkLite.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.WorkerAgent.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.SqlTaskScheduler.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.CustomControls.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.NetEnterpriseServers.ExceptionMessageBox.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.MasterService.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.MasterServiceClient.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Practices.TransientFaultHandling.Core.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Scale.ResourceProvider.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Scale.ScaleoutContract.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ScaleOut.Telemetry.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ScaleOut.Utilities.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationService.Hadoop.Common.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationService.HadoopComponents.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationService.HadoopConnections.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationService.HadoopEnumerators.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationService.HadoopTasks.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.ExceptionMessageBox.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlTools.Telemetry.Interop.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Ssdqs.Component.DataCorrection.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Ssdqs.Component.DataQualityConnectionManager.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.WindowsAzure.Configuration.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.WindowsAzure.Storage.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.WindowsAzure.StorageClient.dll"

# Throws exceptions but likes to be added
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Data.Services.Client.dll" -ErrorAction Stop
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.DataTransfer.Common.dll" -ErrorAction Stop
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.DataTransfer.DataContracts.dll" -ErrorAction Stop
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.AnalysisServices.AppLocal.Tabular.dll" -ErrorAction Stop
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Management.SmoMetadataProvider.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Hadoop.Avro.dll"

# Can't load, won't load
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.Data.DataFeedClient.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.DataTransfer.ClientLibrary.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.ADONETDest.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.ADONETSrc.dllv"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.BulkInsertTask.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.DataReaderDest.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.DataStreaming.Dest.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.DTSPipelineWrap.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.RuntimeTelemetry.dll"
Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.MaintenancePlanTasks.dll"
#>
}

if ($script:serialImport) {
    $scriptBlock.Invoke($script:PSModuleRoot, "$script:DllRoot\smo", (-not $script:strictSecurityMode))
}
else {
    $script:smoRunspace = [System.Management.Automation.PowerShell]::Create()
    if ($script:smoRunspace.Runspace.Name) {
        try { $script:smoRunspace.Runspace.Name = "dbatools-import-smo" }
        catch { }
    }
    $script:smoRunspace.AddScript($scriptBlock).AddArgument($script:PSModuleRoot).AddArgument("$script:DllRoot\smo").AddArgument((-not $script:strictSecurityMode))
    $script:smoRunspace.BeginInvoke()
}