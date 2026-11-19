#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbVirtualLogFile.ps1 at refs/pins/dbatools-2026-10-22: the database selection, the warning for each database it cannot open, then DBCC LOGINFO in
// each of the others, with the caller's database put back.
/// <summary>Retrieves detailed virtual log file (VLF) metadata from transaction logs for performance analysis and troubleshooting.</summary>
/// <para>
/// This function uses DBCC LOGINFO to return detailed metadata about each virtual log file (VLF) within database transaction logs. The output includes VLF size, file offsets, sequence numbers, status, and parity information that's essential for analyzing transaction log structure and performance.
/// </para>
/// <para>
/// Having a transaction log file with too many virtual log files (VLFs) can hurt database performance. Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance.
/// </para>
/// <para>
/// Common use cases include identifying databases with excessive VLF counts (typically over 50-100), analyzing VLF size distribution to spot fragmentation issues, and monitoring VLF status during active transactions. This data helps DBAs make informed decisions about log file growth settings and maintenance schedules.
/// </para>
/// <para>
/// References:
/// http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
/// http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
/// </para>
/// <para>
/// If you've got a high number of VLFs, you can use Expand-DbaDbLogFile to reduce the number.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbVirtualLogFile -SqlInstance sqlcluster
/// </code>
/// <para>
/// Returns all user database virtual log file details for the sqlcluster instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbVirtualLogFile -SqlInstance sqlserver | Group-Object -Property Database | Where-Object Count -gt 50
/// </code>
/// <para>
/// Returns user databases that have 50 or more VLFs.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sqlserver','sqlcluster' | Get-DbaDbVirtualLogFile
/// </code>
/// <para>
/// Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbVirtualLogFile -SqlInstance sqlcluster -Database db1, db2
/// </code>
/// <para>
/// Returns the VLF counts for the db1 and db2 databases on sqlcluster.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Diagnostic, VLF, Database, LogFile
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbVirtualLogFile" />
[Cmdlet(VerbsCommon.Get, "DbaDbVirtualLogFile")]
[OutputType(typeof(System.Collections.ArrayList))]
public sealed class GetDbaDbVirtualLogFileCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
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
    /// Specifies which databases to analyze for VLF information. Accepts wildcards for pattern matching.
    /// Use this when you need to focus on specific databases instead of checking all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies which databases to skip during VLF analysis. Accepts wildcards for pattern matching.
    /// Use this to exclude problematic databases or those you don't need to monitor for VLF issues.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Include system databases (master, model, msdb, tempdb) in the VLF analysis.
    /// By default, only user databases are checked since system database VLF counts are typically less critical for performance tuning.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemDBs { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the virtual log files of the selected databases of each instance.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            List<SmoDatabase>? selected = SelectDatabases(server);
            if (selected is null)
                continue;

            // The name filters run first, so a named database is reported as skipped and an excluded one is never mentioned. Every skip is reported before the first read.
            List<SmoDatabase> accessible = new();
            foreach (SmoDatabase database in selected)
            {
                bool? open = ReadFlag(() => database.IsAccessible);
                if (open == true)
                    accessible.Add(database);
                else if (open == false)
                    WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                        "Skipping {0} on {1} because it is not accessible, so its virtual log files cannot be read", database, instance), database);
            }

            foreach (SmoDatabase database in accessible)
            {
                ErrorRecord? fault = ReportDatabase(server, database);
                if (fault is not null)
                {
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "Unable to query {0} on {1}.", database.Name, instance),
                        target: database, errorRecord: fault, continueLoop: true);
                }
            }
        }
    }

    // PS: if ($Database) and if ($ExcludeDatabase) read truthiness, so a lone empty string filters nothing.
    // Returns null when the server's databases cannot be listed, the fault reported.
    private List<SmoDatabase>? SelectDatabases(Server server)
    {
        bool include = LanguagePrimitives.IsTrue(Database);
        bool exclude = LanguagePrimitives.IsTrue(ExcludeDatabase);
        List<SmoDatabase> databases = new();
        List<string> scope = new();
        try
        {
            foreach (SmoDatabase database in server.Databases)
            {
                databases.Add(database);
                scope.Add(database.Name);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportListFault(failure, include, exclude);
            return null;
        }
        // Correction database-wildcards: the pinned help documents wildcards for both filters, which the literal -in and -NotIn never honoured. Each instance's own names
        // decide which pattern values are real names and stay literal.
        WildcardNameMatcher included = NameMatcher(Database, scope);
        WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, scope);

        List<SmoDatabase> selected = new();
        foreach (SmoDatabase database in databases)
        {
            if (include && !included.Matches(database.Name))
                continue;
            if (exclude && excluded.Matches(database.Name))
                continue;
            // PS: Where-Object IsSystemObject -eq $false. A getter that throws reads as $null there, and $null is not $false.
            if (!IncludeSystemDBs.IsPresent && ReadFlag(() => database.IsSystemObject) != false)
                continue;
            selected.Add(database);
        }
        return selected;
    }

    // PS: SMO loads $server.Databases where the source first walks it, and a failed load stops that statement. $dbs stays the collection, so every later statement that
    // walks it fails the same way and writes its own record: each name filter in use, the system filter unless -IncludeSystemDBs, the skip loop, the IsAccessible filter and
    // the database loop. Then the source goes on to the next instance. Measured on the pin, both editions: evidence/pin-vlf-enum-20261103.txt, enum-*. Under -EnableException
    // the pin writes the same records and goes on; the port stops at the first (acceptedDifferences, list-fault-enable-exception).
    private void ReportListFault(Exception failure, bool include, bool exclude)
    {
        ExtendedTypeSystemException fault = new(String.Format(CultureInfo.InvariantCulture,
            "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure);
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(new ErrorRecord(fault, "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null)); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        }
        int statements = 3 + (include ? 1 : 0) + (exclude ? 1 : 0) + (IncludeSystemDBs.IsPresent ? 0 : 1);
        for (int statement = 0; statement < statements; statement++)
            StatementFault.Surface(this, new ErrorRecord(fault, "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null));
    }

    // PS: -in compares the name with each value; a pattern is tried only on a value the scope does not name.
    private static WildcardNameMatcher NameMatcher(object[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true, (value, name) => PsOps.In(name, new[] { value }), scope);
    }

    // PS: the property read of Where-Object, which reads $null for a getter that throws.
    private static bool? ReadFlag(Func<bool> getter)
    {
        try
        {
            return getter();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // The source's try: the read and the objects written from it. Returns the record its catch block saw, or null.
    private ErrorRecord? ReportDatabase(Server server, SmoDatabase database)
    {
        ErrorRecord? fault = QueryDatabase(database, server.ConnectionContext, out DataTable? files);
        if (fault is not null)
            return fault;
        try
        {
            foreach (DataRow file in files!.Rows)
                WriteObject(FileOutput(server, database, file));
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return StatementFault.Record(failure, "Get-DbaDbVirtualLogFile");
        }
    }

    // PS: the [PSCustomObject] of the source, its properties in order.
    private static PSObject FileOutput(Server server, SmoDatabase database, DataRow file)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Database", database.Name));
        output.Properties.Add(new PSNoteProperty("RecoveryUnitId", Column(file, "RecoveryUnitId")));
        output.Properties.Add(new PSNoteProperty("FileId", Column(file, "FileId")));
        output.Properties.Add(new PSNoteProperty("FileSize", Column(file, "FileSize")));
        output.Properties.Add(new PSNoteProperty("StartOffset", Column(file, "StartOffset")));
        output.Properties.Add(new PSNoteProperty("FSeqNo", Column(file, "FSeqNo")));
        output.Properties.Add(new PSNoteProperty("Status", Column(file, "Status")));
        output.Properties.Add(new PSNoteProperty("Parity", Column(file, "Parity")));
        output.Properties.Add(new PSNoteProperty("CreateLsn", Column(file, "CreateLSN")));
        return output;
    }

    // PS: the dot operator on a DataRow, which reads $null for a column the row does not have: DBCC LOGINFO has no RecoveryUnitId before SQL Server 2012.
    private static object? Column(DataRow row, string name)
    {
        return row.Table.Columns.Contains(name) ? row[name] : null;
    }

    // PS: $db.Query("DBCC LOGINFO"), the pinned Database.Query script method: ExecuteWithResults on the parent's connection, its first table, and in its finally the
    // connection put back. Returns the record the source's catch block saw, or null.
    private ErrorRecord? QueryDatabase(SmoDatabase database, ServerConnection connection, out DataTable? files)
    {
        files = null;
        SetActiveConnection(connection);
        string? previous = ContextDatabase(connection);
        try
        {
            files = database.ExecuteWithResults("DBCC LOGINFO").Tables[0];
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            return new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }
        finally
        {
            PutDatabaseBack(connection, previous);
        }
    }

    // PS: $connectionContext.CurrentDatabase, which reads $null when its getter throws.
    private static string? ContextDatabase(ServerConnection connection)
    {
        try
        {
            return connection.CurrentDatabase;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: the script method's finally. -cne on purpose, because database names follow the instance collation. It never lets a failed USE become the command's outcome: it only warns.
    private void PutDatabaseBack(ServerConnection connection, string? target)
    {
        if (String.IsNullOrEmpty(target) || String.Equals(ContextDatabase(connection), target, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + target!.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNotRestored(String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"", target, failure.Message));
        }
    }

    // The script method raises a Stop or Inquire preference to Continue for this one call, and a caller that asked for silence gets silence. A compiled WriteWarning stops
    // under Stop and prompts under Inquire or -Debug, so it is used only where it cannot: under Continue, or under the caller's variable set to Continue for this one call.
    // A bound -WarningAction other than Continue, or -Debug, leaves only the host's warning line, which shows the same text and cannot stop the command. As recorded for
    // Get-DbaDbPageInfo (restore-warning-bound-preference), there the line cannot be redirected, and elsewhere -WarningVariable also holds it, which the pin's never does.
    private void WarnNotRestored(string text)
    {
        bool actionBound = MyInvocation.BoundParameters.TryGetValue("WarningAction", out object? boundAction);
        ActionPreference wanted = Preference(actionBound ? boundAction : SessionState.PSVariable.GetValue("WarningPreference"));
        if (wanted == ActionPreference.SilentlyContinue)
            return;

        bool debugBound = MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug) && LanguagePrimitives.IsTrue(debug);
        if (actionBound ? wanted != ActionPreference.Continue : debugBound)
        {
            Host?.UI?.WriteWarningLine(text); // style-ok: cs-host-ui a bound Stop, Inquire or Ignore, or -Debug, would end, prompt or drop a WriteWarning the pin raises to Continue
            return;
        }

        if (actionBound || wanted == ActionPreference.Continue)
        {
            WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
            return;
        }

        PSVariable? local = SessionState.PSVariable.Get("local:WarningPreference");
        object? localValue = local?.Value;
        SessionState.PSVariable.Set("local:WarningPreference", ActionPreference.Continue);
        try
        {
            WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
        }
        finally
        {
            if (local is null)
                SessionState.PSVariable.Remove("local:WarningPreference");
            else
                SessionState.PSVariable.Set("local:WarningPreference", localValue);
        }
    }

    // A preference as the engine converts it; anything that does not convert counts as Continue, the engine's default.
    private static ActionPreference Preference(object? value)
    {
        if (value is null)
            return ActionPreference.Continue;
        return LanguagePrimitives.TryConvertTo(value, CultureInfo.InvariantCulture, out ActionPreference preference) ? preference : ActionPreference.Continue;
    }
}
