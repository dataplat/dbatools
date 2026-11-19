#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Rewrites old dbatools command and parameter names in .ps1 files to their current
/// equivalents. Port of public/Invoke-DbatoolsRenameHelper.ps1; Select-String, Get-Content
/// and Set-Content ride the REAL provider cmdlets (per-edition -Encoding semantics). The two
/// rename tables are PS @{} literals, so the port inserts them in source order into
/// case-insensitive Hashtables: enumeration (and therefore cascading-rename and emission
/// order) follows 5.1's deterministic bucket order and stays per-process on net8.0, exactly
/// like the function (W5-014 dynamic-bag class). Surface pinned by
/// migration/baselines/Invoke-DbatoolsRenameHelper.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbatoolsRenameHelper", SupportsShouldProcess = true)]
public sealed class InvokeDbatoolsRenameHelperCommand : DbaBaseCmdlet
{
    /// <summary>The .ps1 files to process; accepts pipeline input.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public System.IO.FileInfo[] InputObject { get; set; } = null!;

    /// <summary>The output file encoding (default UTF8).</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable _paramrenames = null!;
    private Hashtable _commandrenames = null!;

    protected override void BeginProcessing()
    {
        _paramrenames = BuildParamRenames();
        _commandrenames = BuildCommandRenames();
    }

    protected override void ProcessRecord()
    {
        foreach (System.IO.FileInfo fileobject in InputObject)
        {
            string file = fileobject.FullName;
            ApplyRenames(_paramrenames, file);
            ApplyRenames(_commandrenames, file);
        }
    }

    private void ApplyRenames(Hashtable renames, string file)
    {
        foreach (DictionaryEntry name in renames)
        {
            string key = (string)name.Key!;
            string value = (string)name.Value!;
            // PS: if ((Select-String -Pattern "\b$($name.Key)\b" -Path $file))
            Hashtable selectParams = new();
            selectParams["Pattern"] = "\\b" + key + "\\b";
            selectParams["Path"] = file;
            Collection<PSObject> matches = NestedCommand.Invoke(this, "Select-String", selectParams);
            if (matches.Count > 0)
            {
                if (ShouldProcess(file, "Replacing " + key + " with " + value))
                {
                    // PS: ((Get-Content -Path $file -Raw) -Replace "\b$key\b", $value).Trim()
                    // A wildcard-bearing FullName matching several files makes -Raw emit
                    // one string PER file; -Replace applies element-wise and .Trim() rides
                    // member enumeration (also element-wise), then Set-Content writes the
                    // WHOLE resulting value to every matched path (codex r1 F1).
                    Hashtable contentParams = new();
                    contentParams["Path"] = file;
                    contentParams["Raw"] = new SwitchParameter(true);
                    Collection<PSObject> raw = NestedCommand.Invoke(this, "Get-Content", contentParams);
                    List<string> transformed = new();
                    foreach (PSObject rawItem in raw)
                    {
                        string current = rawItem?.BaseObject as string ?? "";
                        transformed.Add(Regex.Replace(current, "\\b" + key + "\\b", value, RegexOptions.IgnoreCase).Trim());
                    }
                    object content;
                    if (transformed.Count == 0)
                        content = "";
                    else if (transformed.Count == 1)
                        content = transformed[0];
                    else
                        content = transformed.ToArray();
                    Hashtable setParams = new();
                    setParams["Path"] = file;
                    setParams["Encoding"] = Encoding;
                    setParams["Value"] = content;
                    NestedCommand.Invoke(this, "Set-Content", setParams);
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("Path", file));
                    output.Properties.Add(new PSNoteProperty("Pattern", key));
                    output.Properties.Add(new PSNoteProperty("ReplacedWith", value));
                    WriteObject(output);
                }
            }
        }
    }

    /// <summary>The $paramrenames PS literal: a PS @{} literal pre-sizes the Hashtable
    /// with its entry count, and the capacity changes the 5.1 bucket order (lab-proven) -
    /// so the port constructs with the same capacity and source insertion order.</summary>
    private static Hashtable BuildParamRenames()
    {
        Hashtable renames = PsHashtable.Literal(18);
        renames.Add("ExcludeAllSystemDb", "ExcludeSystem");
        renames.Add("ExcludeAllUserDb", "ExcludeUser");
        renames.Add("Invoke-Sqlcmd2", "Invoke-DbaQuery");
        renames.Add("NetworkShare", "SharedPath");
        renames.Add("NoDatabases", "ExcludeDatabases");
        renames.Add("NoDisabledJobs", "ExcludeDisabledJobs");
        renames.Add("NoJobs", "ExcludeJobs");
        renames.Add("NoJobSteps", "ExcludeJobSteps");
        renames.Add("NoQueryTextColumn", "ExcludeQueryTextColumn");
        renames.Add("NoSystem", "ExcludeSystemLogins");
        renames.Add("NoSystemDb", "ExcludeSystem");
        renames.Add("NoSystemLogins", "ExcludeSystemLogins");
        renames.Add("NoSystemObjects", "ExcludeSystemObjects");
        renames.Add("NoSystemSpid", "ExcludeSystemSpids");
        renames.Add("UseLastBackups", "UseLastBackup");
        renames.Add("PasswordExpiration", "PasswordExpirationEnabled");
        renames.Add("PasswordPolicy", "PasswordPolicyEnforced");
        renames.Add("ServerInstance", "SqlInstance");
        return renames;
    }

    /// <summary>The $commandrenames PS literal (capacity-sized like the @{} literal).</summary>
    private static Hashtable BuildCommandRenames()
    {
        Hashtable renames = PsHashtable.Literal(215);
        renames.Add("Find-DbaDuplicateIndex", "Find-DbaDbDuplicateIndex");
        renames.Add("Find-DbaDisabledIndex", "Find-DbaDbDisabledIndex");
        renames.Add("Add-DbaRegisteredServer", "Add-DbaRegServer");
        renames.Add("Add-DbaRegisteredServerGroup", "Add-DbaRegServerGroup");
        renames.Add("Backup-DbaDatabaseCertificate", "Backup-DbaDbCertificate");
        renames.Add("Backup-DbaDatabaseMasterKey", "Backup-DbaDbMasterKey");
        renames.Add("Clear-DbaSqlConnectionPool", "Clear-DbaConnectionPool");
        renames.Add("Connect-DbaServer", "Connect-DbaInstance");
        renames.Add("Copy-DbaAgentCategory", "Copy-DbaAgentJobCategory");
        renames.Add("Copy-DbaAgentProxyAccount", "Copy-DbaAgentProxy");
        renames.Add("Copy-DbaAgentSharedSchedule", "Copy-DbaAgentSchedule");
        renames.Add("Copy-DbaCentralManagementServer", "Copy-DbaRegServer");
        renames.Add("Copy-DbaDatabaseAssembly", "Copy-DbaDbAssembly");
        renames.Add("Copy-DbaDatabaseMail", "Copy-DbaDbMail");
        renames.Add("Copy-DbaExtendedEvent", "Copy-DbaXESession");
        renames.Add("Copy-DbaQueryStoreConfig", "Copy-DbaDbQueryStoreOption");
        renames.Add("Copy-DbaSqlDataCollector", "Copy-DbaDataCollector");
        renames.Add("Copy-DbaSqlPolicyManagement", "Copy-DbaPolicyManagement");
        renames.Add("Copy-DbaSqlServerAgent", "Copy-DbaAgentServer");
        renames.Add("Copy-DbaTableData", "Copy-DbaDbTableData");
        renames.Add("Copy-SqlAgentCategory", "Copy-DbaAgentJobCategory");
        renames.Add("Copy-SqlAlert", "Copy-DbaAgentAlert");
        renames.Add("Copy-SqlAudit", "Copy-DbaInstanceAudit");
        renames.Add("Copy-SqlAuditSpecification", "Copy-DbaInstanceAuditSpecification");
        renames.Add("Copy-SqlBackupDevice", "Copy-DbaBackupDevice");
        renames.Add("Copy-SqlCentralManagementServer", "Copy-DbaRegServer");
        renames.Add("Copy-SqlCredential", "Copy-DbaCredential");
        renames.Add("Copy-SqlCustomError", "Copy-DbaCustomError");
        renames.Add("Copy-SqlDatabase", "Copy-DbaDatabase");
        renames.Add("Copy-SqlDatabaseAssembly", "Copy-DbaDbAssembly");
        renames.Add("Copy-SqlDatabaseMail", "Copy-DbaDbMail");
        renames.Add("Copy-SqlDataCollector", "Copy-DbaDataCollector");
        renames.Add("Copy-SqlEndpoint", "Copy-DbaEndpoint");
        renames.Add("Copy-SqlExtendedEvent", "Copy-DbaXESession");
        renames.Add("Copy-SqlJob", "Copy-DbaAgentJob");
        renames.Add("Copy-SqlJobServer", "Copy-SqlInstanceAgent");
        renames.Add("Copy-SqlLinkedServer", "Copy-DbaLinkedServer");
        renames.Add("Copy-SqlLogin", "Copy-DbaLogin");
        renames.Add("Copy-SqlOperator", "Copy-DbaAgentOperator");
        renames.Add("Copy-SqlPolicyManagement", "Copy-DbaPolicyManagement");
        renames.Add("Copy-SqlProxyAccount", "Copy-DbaAgentProxy");
        renames.Add("Copy-SqlResourceGovernor", "Copy-DbaResourceGovernor");
        renames.Add("Copy-SqlInstanceAgent", "Copy-DbaAgentServer");
        renames.Add("Copy-SqlInstanceTrigger", "Copy-DbaInstanceTrigger");
        renames.Add("Copy-SqlSharedSchedule", "Copy-DbaAgentSchedule");
        renames.Add("Copy-SqlSpConfigure", "Copy-DbaSpConfigure");
        renames.Add("Copy-SqlSsisCatalog", "Copy-DbaSsisCatalog");
        renames.Add("Copy-SqlSysDbUserObjects", "Copy-DbaSystemDbUserObject");
        renames.Add("Copy-SqlUserDefinedMessage", "Copy-SqlCustomError");
        renames.Add("Expand-DbaTLogResponsibly", "Expand-DbaDbLogFile");
        renames.Add("Expand-SqlTLogResponsibly", "Expand-DbaDbLogFile");
        renames.Add("Export-DbaDacpac", "Export-DbaDacPackage");
        renames.Add("Export-DbaRegisteredServer", "Export-DbaRegServer");
        renames.Add("Export-SqlLogin", "Export-DbaLogin");
        renames.Add("Export-SqlSpConfigure", "Export-DbaSpConfigure");
        renames.Add("Export-SqlUser", "Export-DbaUser");
        renames.Add("Find-DbaDatabaseGrowthEvent", "Find-DbaDbGrowthEvent");
        renames.Add("Find-SqlDuplicateIndex", "Find-DbaDbDuplicateIndex");
        renames.Add("Find-SqlUnusedIndex", "Find-DbaDbUnusedIndex");
        renames.Add("Get-DbaRegServerName", "Get-DbaRegServer");
        renames.Add("Get-DbaConfig", "Get-DbatoolsConfig");
        renames.Add("Get-DbaConfigValue", "Get-DbatoolsConfigValue");
        renames.Add("Get-DbaDatabaseAssembly", "Get-DbaDbAssembly");
        renames.Add("Get-DbaDatabaseCertificate", "Get-DbaDbCertificate");
        renames.Add("Get-DbaDatabaseEncryption", "Get-DbaDbEncryption");
        renames.Add("Get-DbaDatabaseFile", "Get-DbaDbFile");
        renames.Add("Get-DbaDatabaseFreeSpace", "Get-DbaDbSpace");
        renames.Add("Get-DbaDatabaseMasterKey", "Get-DbaDbMasterKey");
        renames.Add("Get-DbaDatabasePartitionFunction", "Get-DbaDbPartitionFunction");
        renames.Add("Get-DbaDatabasePartitionScheme", "Get-DbaDbPartitionScheme");
        renames.Add("Get-DbaDatabaseSnapshot", "Get-DbaDbSnapshot");
        renames.Add("Get-DbaDatabaseSpace", "Get-DbaDbSpace");
        renames.Add("Get-DbaDatabaseState", "Get-DbaDbState");
        renames.Add("Get-DbaDatabaseUdf", "Get-DbaDbUdf");
        renames.Add("Get-DbaDatabaseUser", "Get-DbaDbUser");
        renames.Add("Get-DbaDatabaseView", "Get-DbaDbView");
        renames.Add("Get-DbaDbQueryStoreOptions", "Get-DbaDbQueryStoreOption");
        renames.Add("Get-DbaDistributor", "Get-DbaRepDistributor");
        renames.Add("Get-DbaInstance", "Connect-DbaInstance");
        renames.Add("Get-DbaJobCategory", "Get-DbaAgentJobCategory");
        renames.Add("Get-DbaLog", "Get-DbaErrorLog");
        renames.Add("Get-DbaLogShippingError", "Get-DbaDbLogShipError");
        renames.Add("Get-DbaOrphanUser", "Get-DbaDbOrphanUser");
        renames.Add("Get-DbaPolicy", "Get-DbaPbmPolicy");
        renames.Add("Get-DbaQueryStoreConfig", "Get-DbaDbQueryStoreOption");
        renames.Add("Get-DbaRegisteredServerGroup", "Get-DbaRegServerGroup");
        renames.Add("Get-DbaRegisteredServerStore", "Get-DbaRegServerStore");
        renames.Add("Get-DbaRestoreHistory", "Get-DbaDbRestoreHistory");
        renames.Add("Get-DbaRoleMember", "Get-DbaDbRoleMember");
        renames.Add("Get-DbaSqlBuildReference", "Get-DbaBuild");
        renames.Add("Get-DbaSqlFeature", "Get-DbaFeature");
        renames.Add("Get-DbaSqlInstanceProperty", "Get-DbaInstanceProperty");
        renames.Add("Get-DbaSqlInstanceUserOption", "Get-DbaInstanceUserOption");
        renames.Add("Get-DbaSqlManagementObject", "Get-DbaManagementObject");
        renames.Add("Get-DbaSqlModule", "Get-DbaModule");
        renames.Add("Get-DbaSqlProductKey", "Get-DbaProductKey");
        renames.Add("Get-DbaSqlRegistryRoot", "Get-DbaRegistryRoot");
        renames.Add("Get-DbaSqlService", "Get-DbaService");
        renames.Add("Get-DbaTable", "Get-DbaDbTable");
        renames.Add("Get-DbaTraceFile", "Get-DbaTrace");
        renames.Add("Get-DbaUserLevelPermission", "Get-DbaUserPermission");
        renames.Add("Get-DbaXEventSession", "Get-DbaXESession");
        renames.Add("Get-DbaXEventSessionTarget", "Get-DbaXESessionTarget");
        renames.Add("Get-DiskSpace", "Get-DbaDiskSpace");
        renames.Add("Get-SqlMaxMemory", "Get-DbaMaxMemory");
        renames.Add("Get-SqlRegisteredServerName", "Get-DbaRegServer");
        renames.Add("Get-SqlInstanceKey", "Get-DbaProductKey");
        renames.Add("Import-DbaCsvToSql", "Import-DbaCsv");
        renames.Add("Import-DbaRegisteredServer", "Import-DbaRegServer");
        renames.Add("Import-SqlSpConfigure", "Import-DbaSpConfigure");
        renames.Add("Install-SqlWhoIsActive", "Install-DbaWhoIsActive");
        renames.Add("Invoke-DbaCmd", "Invoke-DbaQuery");
        renames.Add("Invoke-DbaDatabaseClone", "Invoke-DbaDbClone");
        renames.Add("Invoke-DbaDatabaseShrink", "Invoke-DbaDbShrink");
        renames.Add("Invoke-DbaDatabaseUpgrade", "Invoke-DbaDbUpgrade");
        renames.Add("Invoke-DbaLogShipping", "Invoke-DbaDbLogShipping");
        renames.Add("Invoke-DbaLogShippingRecovery", "Invoke-DbaDbLogShipRecovery");
        renames.Add("Invoke-DbaSqlQuery", "Invoke-DbaQuery");
        renames.Add("Move-DbaRegisteredServer", "Move-DbaRegServer");
        renames.Add("Move-DbaRegisteredServerGroup", "Move-DbaRegServerGroup");
        renames.Add("New-DbaDatabaseCertificate", "New-DbaDbCertificate");
        renames.Add("New-DbaDatabaseMasterKey", "New-DbaDbMasterKey");
        renames.Add("New-DbaDatabaseSnapshot", "New-DbaDbSnapshot");
        renames.Add("New-DbaPublishProfile", "New-DbaDacProfile");
        renames.Add("New-DbaSqlConnectionString", "New-DbaConnectionString");
        renames.Add("New-DbaSqlConnectionStringBuilder", "New-DbaConnectionStringBuilder");
        renames.Add("New-DbaSqlDirectory", "New-DbaDirectory");
        renames.Add("Out-DbaDataTable", "ConvertTo-DbaDataTable");
        renames.Add("Publish-DbaDacpac", "Publish-DbaDacPackage");
        renames.Add("Read-DbaXEventFile", "Read-DbaXEFile");
        renames.Add("Register-DbaConfig", "Register-DbatoolsConfig");
        renames.Add("Remove-DbaDatabaseCertificate", "Remove-DbaDbCertificate");
        renames.Add("Remove-DbaDatabaseMasterKey", "Remove-DbaDbMasterKey");
        renames.Add("Remove-DbaDatabaseSnapshot", "Remove-DbaDbSnapshot");
        renames.Add("Remove-DbaOrphanUser", "Remove-DbaDbOrphanUser");
        renames.Add("Remove-DbaRegisteredServer", "Remove-DbaRegServer");
        renames.Add("Remove-DbaRegisteredServerGroup", "Remove-DbaRegServerGroup");
        renames.Add("Remove-SqlDatabaseSafely", "Remove-DbaDatabaseSafely");
        renames.Add("Remove-SqlOrphanUser", "Remove-DbaDbOrphanUser");
        renames.Add("Repair-DbaOrphanUser", "Repair-DbaDbOrphanUser");
        renames.Add("Repair-SqlOrphanUser", "Repair-DbaDbOrphanUser");
        renames.Add("Reset-SqlAdmin", "Reset-DbaAdmin");
        renames.Add("Reset-SqlSaPassword", "Reset-SqlAdmin");
        renames.Add("Restart-DbaSqlService", "Restart-DbaService");
        renames.Add("Restore-DbaDatabaseCertificate", "Restore-DbaDbCertificate");
        renames.Add("Restore-DbaDatabaseSnapshot", "Restore-DbaDbSnapshot");
        renames.Add("Restore-HallengrenBackup", "Restore-SqlBackupFromDirectory");
        renames.Add("Set-DbaConfig", "Set-DbatoolsConfig");
        renames.Add("Get-DbaBackupHistory", "Get-DbaDbBackupHistory");
        renames.Add("Set-DbaDatabaseOwner", "Set-DbaDbOwner");
        renames.Add("Set-DbaDatabaseState", "Set-DbaDbState");
        renames.Add("Set-DbaDbQueryStoreOptions", "Set-DbaDbQueryStoreOption");
        renames.Add("Set-DbaJobOwner", "Set-DbaAgentJobOwner");
        renames.Add("Set-DbaQueryStoreConfig", "Set-DbaDbQueryStoreOption");
        renames.Add("Set-DbaTempDbConfiguration", "Set-DbaTempdbConfig");
        renames.Add("Set-SqlMaxMemory", "Set-DbaMaxMemory");
        renames.Add("Set-SqlTempDbConfiguration", "Set-DbaTempdbConfig");
        renames.Add("Show-DbaDatabaseList", "Show-DbaDbList");
        renames.Add("Show-SqlDatabaseList", "Show-DbaDbList");
        renames.Add("Show-SqlMigrationConstraint", "Test-SqlMigrationConstraint");
        renames.Add("Show-SqlInstanceFileSystem", "Show-DbaInstanceFileSystem");
        renames.Add("Show-SqlWhoIsActive", "Invoke-DbaWhoIsActive");
        renames.Add("Start-DbaSqlService", "Start-DbaService");
        renames.Add("Start-SqlMigration", "Start-DbaMigration");
        renames.Add("Stop-DbaSqlService", "Stop-DbaService");
        renames.Add("Sync-DbaSqlLoginPermission", "Sync-DbaLoginPermission");
        renames.Add("Sync-SqlLoginPermissions", "Sync-DbaLoginPermission");
        renames.Add("Test-DbaDatabaseCollation", "Test-DbaDbCollation");
        renames.Add("Test-DbaDatabaseCompatibility", "Test-DbaDbCompatibility");
        renames.Add("Test-DbaDatabaseOwner", "Test-DbaDbOwner");
        renames.Add("Test-DbaDbVirtualLogFile", "Measure-DbaDbVirtualLogFile");
        renames.Add("Test-DbaFullRecoveryModel", "Test-DbaDbRecoveryModel");
        renames.Add("Test-DbaJobOwner", "Test-DbaAgentJobOwner");
        renames.Add("Test-DbaLogShippingStatus", "Test-DbaDbLogShipStatus");
        renames.Add("Test-DbaRecoveryModel", "Test-DbaDbRecoveryModel");
        renames.Add("Test-DbaSqlBuild", "Test-DbaBuild");
        renames.Add("Test-DbaSqlManagementObject", "Test-DbaManagementObject");
        renames.Add("Test-DbaSqlPath", "Test-DbaPath");
        renames.Add("Test-DbaTempDbConfiguration", "Test-DbaTempdbConfig");
        renames.Add("Test-DbaValidLogin", "Test-DbaWindowsLogin");
        renames.Add("Test-DbaVirtualLogFile", "Measure-DbaDbVirtualLogFile");
        renames.Add("Test-SqlConnection", "Test-DbaConnection");
        renames.Add("Test-SqlDiskAllocation", "Test-DbaDiskAllocation");
        renames.Add("Test-SqlMigrationConstraint", "Test-DbaMigrationConstraint");
        renames.Add("Test-SqlNetworkLatency", "Test-DbaNetworkLatency");
        renames.Add("Test-SqlPath", "Test-DbaPath");
        renames.Add("Test-SqlTempDbConfiguration", "Test-DbaTempdbConfig");
        renames.Add("Update-DbaSqlServiceAccount", "Update-DbaServiceAccount");
        renames.Add("Watch-DbaXEventSession", "Watch-DbaXESession");
        renames.Add("Watch-SqlDbLogin", "Watch-DbaDbLogin");
        renames.Add("Add-DbaCmsRegServer", "Add-DbaRegServer");
        renames.Add("Add-DbaCmsRegServerGroup", "Add-DbaRegServerGroup");
        renames.Add("Copy-DbaCmsRegServer", "Copy-DbaRegServer");
        renames.Add("Export-DbaCmsRegServer", "Export-DbaRegServer");
        renames.Add("Get-DbaCmsRegistryRoot", "Get-DbaRegistryRoot");
        renames.Add("Get-DbaCmsRegServer", "Get-DbaRegServer");
        renames.Add("Get-DbaCmsRegServerGroup", "Get-DbaRegServerGroup");
        renames.Add("Get-DbaCmsRegServerStore", "Get-DbaRegServerStore");
        renames.Add("Import-DbaCmsRegServer", "Import-DbaRegServer");
        renames.Add("Move-DbaCmsRegServer", "Move-DbaRegServer");
        renames.Add("Move-DbaCmsRegServerGroup", "Move-DbaRegServerGroup");
        renames.Add("Remove-DbaCmsRegServer", "Remove-DbaRegServer");
        renames.Add("Remove-DbaCmsRegServerGroup", "Remove-DbaRegServerGroup");
        renames.Add("Copy-DbaServerAuditSpecification", "Copy-DbaInstanceAuditSpecification");
        renames.Add("Copy-DbaServerAudit", "Copy-DbaInstanceAudit");
        renames.Add("Copy-DbaServerTrigger", "Copy-DbaInstanceTrigger");
        renames.Add("Test-DbaServerName", "Test-DbaInstanceName");
        renames.Add("Test-DbaInstanceName", "Repair-DbaInstanceName");
        renames.Add("Get-DbaServerTrigger", "Get-DbaInstanceTrigger");
        renames.Add("Get-DbaServerAudit", "Get-DbaInstanceAudit");
        renames.Add("Get-DbaServerAuditSpecification", "Get-DbaInstanceAuditSpecification");
        renames.Add("Get-DbaServerInstallDate", "Get-DbaInstanceInstallDate");
        renames.Add("Show-DbaServerFileSystem", "Show-DbaInstanceFileSystem");
        renames.Add("Install-DbaWatchUpdate", "Install-DbatoolsWatchUpdate");
        renames.Add("Uninstall-DbaWatchUpdate", "Uninstall-DbatoolsWatchUpdate");
        return renames;
    }
}
