$scriptBlock = {
	Param (
		$ModuleRoot
	)
	
	try
	{
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.BatchParser.dll" -ErrorAction Stop
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.BatchParserClient.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.BulkInsertTaskConnections.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DTSRuntimeWrap.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DtsServer.Interop.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DTSUtilities.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ForEachFileEnumeratorWrap.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ManagedDTS.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ODataConnectionManager.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ODataSrc.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.PipelineHost.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.PackageFormatUpdate.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Replication.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SqlCEDest.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SQLTask.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TxScript.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XE.Core.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XEvent.Configuration.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XEvent.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XEvent.Linq.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XmlSrc.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Rmo.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DTSPipelineWrap.dll"
		Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ScriptTask.dll" -ErrorAction Stop
	}
	catch
	{
		# don't care ;)
	}
	
	Add-Type -Path "$ModuleRoot\bin\smo\Accessibility.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\EnvDTE.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.AnalysisServices.AppLocal.Core.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.AnalysisServices.AppLocal.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.Azure.KeyVault.Core.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.Data.Edm.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.Data.OData.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.Practices.TransientFaultHandling.Core.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.DataTransfer.Common.Utils.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ASTasks.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ConnectionInfo.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ConnectionInfoExtended.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DataProfiler.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DataProfilingTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Diagnostics.STrace.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Dmf.Common.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Dmf.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DMQueryTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DTEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Dts.Design.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Dts.DtsClient.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DtsMsg.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Edition.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ExecProcTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ExpressionTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.FileSystemTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ForEachADOEnumerator.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ForEachFromVarEnumerator.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ForEachNodeListEnumerator.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ForEachSMOEnumerator.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.FtpTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.GridControl.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Instapi.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ClusterManagement.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Common.ObjectModel.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.ISServerDBUpgrade.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Server.Common.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Server.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.Server.IPC.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.server.shared.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.IntegrationServices.TaskScheduler.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ManagedConnections.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.Collector.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.CollectorEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.CollectorTasks.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.HadrDMF.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.HelpViewer.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.IntegrationServices.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.IntegrationServicesEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.RegisteredServers.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.Sdk.Sfc.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.SmartAdminPolicies.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.SqlParser.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.SystemMetadataProvider.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.Utility.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.UtilityEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.XEvent.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.XEventDbScoped.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.XEventDbScopedEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Management.XEventEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.MSMQTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.PipelineXML.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.PolicyEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.RegSvrEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Replication.BusinessLogicSupport.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SendMailTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.ServiceBrokerEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Smo.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SmoExtended.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SqlClrProvider.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SqlEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SQLTaskConnectionsWrap.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SqlTDiagM.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SqlWmiManagement.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.SString.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferDatabasesTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferErrorMessagesTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferJobsTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferLoginsTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferObjectsTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferSqlServerObjectsTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.TransferStoredProceduresTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Types.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Types.resources.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.VSTAScriptingLib.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.WebServiceTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.WMIDRTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.WmiEnum.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.WMIEWTask.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.XMLTask.dll"
	# x86
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.Dmf.Adapters.dll"
	Add-Type -Path "$ModuleRoot\bin\smo\Microsoft.SqlServer.DmfSqlClrWrapper.dll"
	
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
	$scriptBlock.Invoke($script:PSModuleRoot)
}
else {
	$script:smoRunspace = [System.Management.Automation.PowerShell]::Create()
	try { $script:smoRunspace.Runspace.Name = "dbatools-import-smo" }
	catch { }
	$script:smoRunspace.AddScript($scriptBlock).AddArgument($script:PSModuleRoot)
	$script:smoRunspace.BeginInvoke()
}