#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves database state information including read/write status, availability, and user access mode
/// </summary>
/// <para>
/// Gets three key database state properties from sys.databases that DBAs frequently need to check:
/// - "RW" options: READ_ONLY or READ_WRITE (whether database accepts modifications)
/// - "Status" options: ONLINE, OFFLINE, EMERGENCY, RESTORING (database availability state)
/// - "Access" options: SINGLE_USER, RESTRICTED_USER, MULTI_USER (user connection restrictions)
/// </para>
/// <para>
/// This function is useful for quickly auditing database configurations across instances, especially when troubleshooting connectivity issues or preparing for maintenance operations. System databases (master, model, msdb, tempdb, distribution) are excluded by default since their states rarely change.
/// </para>
/// <para>
/// Returns an object with SqlInstance, DatabaseName, RW, Status, and Access properties for each user database.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbState -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Gets options for all databases of the sqlserver2014a instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbState -SqlInstance sqlserver2014a -Database HR, Accounting
/// </code>
/// <para>
/// Gets options for both HR and Accounting database of the sqlserver2014a instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbState -SqlInstance sqlserver2014a -Exclude HR
/// </code>
/// <para>
/// Gets options for all databases of the sqlserver2014a instance except HR
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sqlserver2014a', 'sqlserver2014b' | Get-DbaDbState
/// </code>
/// <para>
/// Gets options for all databases of sqlserver2014a and sqlserver2014b instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Database
/// Author: Simone Bizzotto (@niphlod)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// <item><term>OUTPUTS</term><description>
/// <para>PSCustomObject</para>
/// <para>Returns one object per database queried. Each object contains the database state information for a specific database on the target instance.</para>
/// <para>Default display properties (via Select-DefaultView):</para>
/// <para>- SqlInstance: The SQL Server instance name (computer\instance or just computer)</para>
/// <para>- InstanceName: The SQL Server service name (instance name only)</para>
/// <para>- ComputerName: The computer name where the SQL Server instance is running</para>
/// <para>- DatabaseName: The name of the database</para>
/// <para>- RW: The read/write status (READ_WRITE or READ_ONLY)</para>
/// <para>- Status: The database availability state (ONLINE, OFFLINE, EMERGENCY, or RESTORING)</para>
/// <para>- Access: The user connection restriction level (SINGLE_USER, RESTRICTED_USER, or MULTI_USER)</para>
/// <para>Additional properties available:</para>
/// <para>- Database: The SMO Database object for this database (hidden from default display)</para>
/// </description></item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbState" />
[Cmdlet(VerbsCommon.Get, "DbaDbState")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaDbStateCommand : DbaInstanceCmdlet
{
    private const string DbStatesQuery = @"SELECT
Name   = name,
Access = user_access_desc,
Status = state_desc,
RW     = CASE WHEN is_read_only = 0 THEN 'READ_WRITE' ELSE 'READ_ONLY' END
FROM sys.databases";

    private const string DbStatesQuery2000 = @"SELECT
Name   = name,
Access = DATABASEPROPERTYEX(name, 'UserAccess'),
Status = DATABASEPROPERTYEX(name, 'Status'),
RW     = DATABASEPROPERTYEX(name, 'Updateability')
FROM sys.databases";

    /// <para>
    /// The target SQL Server instance or instances
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which user databases to check for state information. Accepts multiple database names as an array.
    /// Use this when you need to audit specific databases rather than checking all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies which user databases to exclude from the state check. Accepts multiple database names as an array.
    /// Use this when you want to check most databases but skip specific ones, such as databases under maintenance.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
            {
                continue;
            }

            DataTable dbStates;
            try
            {
                dbStates = server.ConnectionContext.ExecuteWithResults(
                    server.VersionMajor == 8 ? DbStatesQuery2000 : DbStatesQuery).Tables[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ErrorRecord record = new(NativeServerQuery.QueryMethodException(failure),
                    "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
                // caller-try: terminate -- -EnableException explicitly stops on the failed query.
                if (EnableException)
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve explicit terminating query errors
                StatementFault.Surface(this, record);
                continue;
            }

            // PS: "normal" hashtable doesn't account for case sensitivity
            Dictionary<string, DataRow> dbStatesHash = new(StringComparer.Ordinal);
            foreach (DataRow stateRow in dbStates.Rows)
            {
                dbStatesHash[(string)stateRow["Name"]] = stateRow;
            }

            string[] systemDatabases = { "master", "model", "msdb", "tempdb", "distribution" };

            foreach (DataRow db in dbStates.Rows)
            {
                string name = (string)db["Name"];
                bool isSystem = false;
                foreach (string sysDb in systemDatabases)
                {
                    if (string.Equals(sysDb, name, StringComparison.OrdinalIgnoreCase))
                    {
                        isSystem = true;
                        break;
                    }
                }
                if (isSystem)
                {
                    continue;
                }
                if (LanguagePrimitives.IsTrue(Database) && !NativeDatabaseSelection.ContainsInOperand(Database, name))
                {
                    continue;
                }
                if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, name))
                {
                    continue;
                }

                DataRow dbStatus = dbStatesHash[name];
                PSObject result = new();
                // PS emission order preserved: SqlInstance ($server.Name), InstanceName, ComputerName first
                result.Properties.Add(new PSNoteProperty("SqlInstance", server.Name));
                result.Properties.Add(new PSNoteProperty("InstanceName",
                    server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase ? null : server.ServiceName));
                result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server)));
                result.Properties.Add(new PSNoteProperty("DatabaseName", name));
                result.Properties.Add(new PSNoteProperty("RW", dbStatus["RW"]));
                result.Properties.Add(new PSNoteProperty("Status", dbStatus["Status"]));
                result.Properties.Add(new PSNoteProperty("Access", dbStatus["Access"]));
                result.Properties.Add(new PSNoteProperty("Database", server.Databases[name]));

                // PS: Select-DefaultView -ExcludeProperty Database
                OutputHelper.SetDefaultDisplayPropertySetExcluding(result, new[] { "Database" });

                WriteObject(result);
            }
        }
    }

}
