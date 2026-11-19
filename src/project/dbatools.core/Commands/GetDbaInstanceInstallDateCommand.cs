#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server installation dates by querying system tables for compliance auditing and infrastructure tracking.
/// </summary>
/// <para>
/// Queries system tables (sys.server_principals or sysservers) to determine when SQL Server was originally installed on each target instance. This information is essential for compliance auditing, license management, and tracking hardware refresh cycles. The function automatically handles different SQL Server versions using the appropriate system table, and can optionally retrieve the Windows OS installation date through WMI for complete infrastructure documentation. Returns structured data including computer name, instance name, and precise installation timestamps.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceInstallDate -SqlInstance SqlBox1\Instance2
/// </code>
/// <para>
/// Returns an object with SQL Instance Install date as a string.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceInstallDate -SqlInstance winserver\sqlexpress, sql2016
/// </code>
/// <para>
/// Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sqlserver2014a', 'sql2016' | Get-DbaInstanceInstallDate
/// </code>
/// <para>
/// Returns an object with SQL Instance Install date as a string for both SQLInstances that are passed to the cmdlet via the pipeline.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceInstallDate -SqlInstance sqlserver2014a, sql2016 -IncludeWindows
/// </code>
/// <para>
/// Returns an object with the Windows Install date and the SQL install date as a string.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServer -SqlInstance sql2014 | Get-DbaInstanceInstallDate
/// </code>
/// <para>
/// Returns an object with SQL Instance install date as a string for every server listed in the Central Management Server on sql2014
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Install, Instance, Utility
/// Author: Mitchell Hamann (@SirCaptainMitch), mitchellhamann.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaInstanceInstallDate" />
[Cmdlet(VerbsCommon.Get, "DbaInstanceInstallDate")]
public sealed class GetDbaInstanceInstallDateCommand : DbaInstanceCmdlet
{
    private const string PrincipalQuery = "SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000";
    private const string ServersQuery = "SELECT schemadate FROM dbo.sysservers";

    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "SqlInstallDate" };
    private static readonly string[] WindowsDisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "SqlInstallDate", "WindowsInstallDate" };

    // The install date of the instance being read. The pin's $sqlInstallDate lives in the function's scope, so a query that
    // faults left the date the previous instance gave under this one; each instance starts with none here (correction
    // stale-install-date).
    private object? _sqlInstallDate;

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
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
    /// Windows credentials used for WMI connection when retrieving Windows OS installation date with -IncludeWindows.
    /// Only required when the current user lacks WMI access to the target server or when connecting across domains.
    /// </para>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <para>
    /// Retrieves the Windows OS installation date in addition to SQL Server installation date using WMI.
    /// Useful for infrastructure audits requiring both application and operating system installation timestamps.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeWindows { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
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
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            _sqlInstallDate = null;

            // PS: if ($server.VersionMajor -ge 9): the connection refuses anything older, so the sysservers branch for SQL
            // Server 2000 is gone (SQL Server 2000/2005 stripped).
            WriteMessage(MessageLevel.Verbose, "Getting Install Date for: " + instance);
            AssignInstallDate(server, PrincipalQuery, "create_date");

            // PS: if (-not $sqlInstallDate -or $sqlInstallDate -is [System.DBNull]): a typed DbaDateTime is never DBNull.
            if (!LanguagePrimitives.IsTrue(_sqlInstallDate))
            {
                WriteMessage(MessageLevel.Verbose, "Trying again to get Install Date for: " + instance);
                AssignInstallDate(server, ServersQuery, "schemadate");
            }

            // PS: $WindowsServerName = $server.ComputerNamePhysicalNetBIOS. A property read through the member binder: a
            // failing getter is $null with no record. Azure SQL Database is the case met: compiled SMO throws
            // UnknownPropertyException there, the pin reads null with no warning or error (probe evidence
            // pin-installdate-20261105.txt, both editions).
            string? windowsServerName;
            try
            {
                windowsServerName = server.ComputerNamePhysicalNetBIOS;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                windowsServerName = null;
            }

            object? windowsInstallDate = null;
            if (IncludeWindows.ToBool())
            {
                // PS: try { [DbaDateTime]$windowsInstallDate = (Get-DbaCmObject -ClassName win32_OperatingSystem
                //     -ComputerName $WindowsServerName -Credential $Credential -EnableException).InstallDate }
                //     catch { Stop-Function -Message "Failed to connect to: $WindowsServerName" -Continue -Target $instance -ErrorRecord $_ }
                try
                {
                    windowsInstallDate = ToDbaDateTime(ReadOperatingSystemInstallDate(windowsServerName));
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    StopFunction("Failed to connect to: " + windowsServerName, target: instance, errorRecord: CaughtRecord(failure), continueLoop: true);
                    continue;
                }
            }

            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("SqlInstallDate", _sqlInstallDate));
            output.Properties.Add(new PSNoteProperty("WindowsInstallDate", windowsInstallDate));
            OutputHelper.SetDefaultDisplayPropertySet(output, IncludeWindows.ToBool() ? WindowsDisplaySet : DisplaySet);
            WriteObject(output);
        }
    }

    // PS: [DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).<column>. A failed query or conversion is the
    // engine's statement fault: the pin writes it, keeps the value it had and goes on to the next statement.
    private void AssignInstallDate(Server server, string sql, string column)
    {
        // The Server.Query script method with a database runs Databases[$Database].ExecuteWithResults on the caller's
        // connection and, in its finally, puts the caller's database back (#10555) before any fault leaves it; with
        // $AllTables it writes each table, which member access then reads row by row.
        ServerConnection connection = server.ConnectionContext;
        string previous = connection.CurrentDatabase;
        DataSet? results = null;
        Exception? queryFailure = null;
        try
        {
            results = server.Databases["master"].ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            queryFailure = failure;
        }
        finally
        {
            PutDatabaseBack(connection, previous);
        }

        if (queryFailure is not null)
        {
            ReportFault(QueryFaultRecord(queryFailure));
            return;
        }

        List<object?> values = new();
        if (results is not null)
        {
            foreach (DataTable table in results.Tables)
            {
                foreach (DataRow row in table.Rows)
                    values.Add(row[column]);
            }
        }

        object? value = MemberValue(values);

        try
        {
            _sqlInstallDate = ToDbaDateTime(value);
        }
        catch (ArgumentTransformationMetadataException failure)
        {
            ReportFault(new ErrorRecord(failure.ErrorRecord, failure));
        }
    }

    // PS: Get-DbaCmObject -ClassName win32_OperatingSystem -ComputerName $WindowsServerName -Credential $Credential -EnableException,
    // then .InstallDate. A null name binds and reads nothing; a name the parameter cannot take stops the nested command with its
    // "Failed to interpret input" record; when the run gives up, the nested Stop-Function throws its record
    // (CmObjectFailureRecord gives the pin's call for each kind).
    private object? ReadOperatingSystemInstallDate(string? computerName)
    {
        if (computerName is null)
            return null;

        DbaCmConnectionParameter target = new(computerName);
        if (!target.Success)
        {
            // The pin prints $connectionObject.Input, a member this type does not have, so the text ends after the colon.
            throw new NestedCmObjectFault(CaughtNestedStopFunction("Get-DbaCmObject", "Failed to interpret input: ", category: ErrorCategory.InvalidArgument));
        }

        string computer = target.Connection.ComputerName.ToLowerInvariant();
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectRequest request = new()
        {
            ComputerName = computer,
            Credential = Credential,
            ClassName = "win32_OperatingSystem",
            Observer = new CimService.CmObjectObserver
            {
                Rung = (rung, step, error) => lastRung = rung,
                Failure = reported => failure = reported
            }
        };

        CimService.CmObjectResult result;
        try
        {
            result = CimService.GetCmObject(this, request);
        }
        catch (Exception) when (failure is not null)
        {
            CmObjectFailureRecord? report = CmObjectFailureRecord.Build(failure!, target.Connection, computer, lastRung, true, "win32_OperatingSystem", "root\\cimv2");
            if (report is null)
                throw;
            throw new NestedCmObjectFault(CaughtNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category,
                report.OverrideExceptionMessage));
        }

        foreach (ErrorRecord record in result.PassthroughErrors)
            WriteError(record);

        List<object?> values = new();
        foreach (PSObject item in result.Instances)
            values.Add(item.Properties["InstallDate"]?.Value);
        return MemberValue(values);
    }

    // Member access over a collection: none gives null, one gives its value, more give them all.
    private static object? MemberValue(List<object?> values)
    {
        if (values.Count == 0)
            return null;
        if (values.Count == 1)
            return values[0];
        return values.ToArray();
    }

    // The [DbaDateTime] type constraint: the engine's conversion, whose failure is the variable's transformation error.
    private static object? ToDbaDateTime(object? value)
    {
        try
        {
            return LanguagePrimitives.ConvertTo(value, typeof(DbaDateTime), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException failure)
        {
            throw new ArgumentTransformationMetadataException(failure.Message, failure);
        }
    }

    // The record the pinned catch receives as $_: the nested Get-DbaCmObject's thrown record, the type constraint's record,
    // or the failure itself.
    private static ErrorRecord CaughtRecord(Exception failure)
    {
        if (failure is NestedCmObjectFault nested)
            return nested.Record;
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // The error record of a failed $server.Query: the script method concatenates the messages of the ExecuteWithResults
    // failure chain and throws that text, which the engine reports as the ScriptMethodRuntimeException fault of "Query"
    // called with three arguments.
    private static ErrorRecord QueryFaultRecord(Exception exception)
    {
        string message = "";
        Exception inner = exception;
        while (inner.InnerException is not null)
        {
            message += inner.Message;
            inner = inner.InnerException;
        }

        message += inner.Message;
        MethodInvocationException fault = new(
            string.Format(CultureInfo.InvariantCulture, "Exception calling \"Query\" with \"3\" argument(s): \"{0}\"", message), new RuntimeException(message));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    // The Server.Query script method's finally: compared case-sensitively, USE [...] with ] doubled, and only a warning when
    // that fails, through plain Write-Warning with a Stop or Inquire preference raised to Continue.
    private void PutDatabaseBack(ServerConnection connection, string? database)
    {
        if (string.IsNullOrEmpty(database) || string.Equals(connection.CurrentDatabase, database, StringComparison.Ordinal))
            return;
        string warning;
        try
        {
            connection.ExecuteNonQuery("USE [" + database!.Replace("]", "]]") + "]");
            return;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            warning = string.Format(CultureInfo.InvariantCulture, "The database context could not be restored to [{0}]: {1}", database,
                "Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"" + failure.Message + "\"");
        }

        try
        {
            WriteWarning(warning); // style-ok: cs-raw-streams the Server.Query script method calls plain Write-Warning, not Write-Message
        }
        catch (ActionPreferenceStopException stopped)
        {
            // The preference the script method raises to Continue must not end the command here.
            WriteMessage(MessageLevel.Debug, stopped.Message);
        }
    }

    // A statement of the pin's body with no try around it: a plain call writes the record and goes on, a caller's try
    // catches it, -EnableException stops here (the keep-going section's accepted difference).
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        StatementFault.Surface(this, fault);
    }

    // Carries the nested Get-DbaCmObject's thrown record from the call to the pinned catch.
    private sealed class NestedCmObjectFault : Exception
    {
        internal NestedCmObjectFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
