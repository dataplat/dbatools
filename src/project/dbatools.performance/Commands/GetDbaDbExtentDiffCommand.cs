#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbExtentDiff.ps1 at refs/pins/dbatools-2026-10-22: a non-pooled Connect-DbaInstance that closes only
// what it opened, then sys.dm_db_file_space_usage from 2016 SP2, or the DBCC PAGE differential bitmaps before it.
/// <summary>Calculates the percentage of database extents modified since the last full backup</summary>
/// <para>
/// Analyzes database extents to determine how much data has changed since the last full backup, helping DBAs decide between differential and full backup strategies. The function examines extent-level modifications (groups of 8 pages) to provide accurate change percentages, which is essential for optimizing backup schedules and storage requirements.
/// </para>
/// <para>
/// For SQL Server 2016 SP2 and later, uses the sys.dm_db_file_space_usage DMV for efficient analysis. For older versions, falls back to DBCC PAGE commands to examine differential bitmap pages directly.
/// </para>
/// <para>
/// Based on the original script by Paul S. Randal: https://www.sqlskills.com/blogs/paul/new-script-how-much-of-the-database-has-changed-since-the-last-full-backup/
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbExtentDiff -SqlInstance SQL2016 -Database DBA
/// </code>
/// <para>
/// Get the changes for the DBA database.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $Cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbExtentDiff -SqlInstance SQL2017N1, SQL2017N2, SQL2016 -Database DB01 -SqlCredential $Cred
/// </code>
/// <para>
/// Get the changes for the DB01 database on multiple servers.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Backup, Database
/// Author: Viorel Ciucu, cviorel.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbExtentDiff" />
[Cmdlet(VerbsCommon.Get, "DbaDbExtentDiff")]
public sealed class GetDbaDbExtentDiffCommand : DbaInstanceCmdlet
{
    // PS: #Available from 2016 SP2
    private static readonly Version FileSpaceUsageVersion = new(13, 0, 5026);

    // PS: $rex = [regex]':(?<extent>[\d]+)\)'
    private static readonly Regex ExtentPattern = new(@":(?<extent>[\d]+)\)");

    private const string FileSpaceUsageSql = "SELECT SUM(total_page_count) / 8 AS [ExtentsTotal], SUM(modified_extent_page_count) / 8 AS [ExtentsChanged], 100.0 * SUM(modified_extent_page_count)/SUM(total_page_count) AS [ChangedPerc] FROM {0}sys.dm_db_file_space_usage";

    private const string MasterFilesSql = "SELECT [file_id], [size], database_id, DB_NAME(database_id) AS dbname FROM master.sys.master_files WHERE [type_desc] = N'ROWS'";

    // Correction dbcc-page-name: the database goes by its id, so no name text reaches the batch.
    private const string PageSql = "DBCC PAGE ({0}, {1}, {2}, 3)  WITH TABLERESULTS, NO_INFOMSGS";

    /// <para>
    /// The target SQL Server instance
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
    /// Specifies which databases to analyze for extent changes since the last full backup. Accepts multiple database names and supports wildcards.
    /// Use this when you need to check specific databases rather than analyzing all databases on the instance, which is helpful for large environments or when focusing on particular applications.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Specifies databases to skip during the extent change analysis. Accepts multiple database names and supports wildcards.
    /// Use this to exclude system databases, read-only databases, or databases where you don't need backup planning analysis, reducing execution time and focusing on relevant databases.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Reads each instance through the form its version supports.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = Connect(instance, out bool isNewConnection);
            if (server is null)
                continue;

            try
            {
                List<SmoDatabase> databases = SelectDatabases(server, instance);
                // Correction azure-database-read: Azure SQL Database reports version 12 and has the view but no master_files.
                if (IsAzure(server) || server.Version >= FileSpaceUsageVersion)
                    ReadFileSpaceUsage(server, databases);
                else
                    ReadBitmaps(server, databases);
            }
            finally
            {
                // PS: closing a connection of the caller takes their session with it, so only what this opened (#10554).
                if (isNewConnection)
                    Disconnect(server);
            }
        }
    }

    // PS: Connect-DbaInstance -NonPooledConnection -IsNewConnectionReference, which throws to its caller by default.
    private Server? Connect(DbaInstanceParameter instance, out bool isNewConnection)
    {
        isNewConnection = false;
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                NonPooledConnection = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "NonPooledConnection" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            };
            request.ApplyConfigurationDefaults();
            ConnectionResolution resolution = ConnectionService.ResolveInstance(request);
            ConnectionService.FinalizeConnection(resolution, request);
            isNewConnection = resolution.IsNewConnection;
            SetActiveConnection(resolution.Server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return resolution.Server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDbExtentDiff", ErrorCategory.ConnectionError, instance);
            StopFunction(String.Format("Error occurred while establishing connection to {0}", instance), target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
            return null;
        }
    }

    // PS: $null = $server | Disconnect-DbaInstance closes the connection and takes it out of the connection hash.
    private void Disconnect(Server server)
    {
        try
        {
            server.ConnectionContext.Disconnect();
            if (ConnectionHost.ActiveConnections.Remove(server.ConnectionContext.ConnectionString))
                WriteAttributedMessage("Disconnect-DbaInstance", MessageLevel.Verbose, "removing from connection hash");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "Disconnect-DbaInstance", ErrorCategory.NotSpecified, server);
            WarnNestedStopFunction("Disconnect-DbaInstance", String.Format("Failed to disconnect {0}", server), server, record, ErrorCategory.NotSpecified);
        }
    }

    // PS: $server.Databases, Name -In $Database, Name -NotIn $ExcludeDatabase, then the accessible ones.
    private List<SmoDatabase> SelectDatabases(Server server, DbaInstanceParameter instance)
    {
        List<SmoDatabase> available = new();
        foreach (SmoDatabase database in server.Databases)
            available.Add(database);
        List<string> names = available.ConvertAll(item => item.Name);
        WildcardNameMatcher included = NameMatcher(Database, names);
        WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, names);

        List<SmoDatabase> selected = new();
        foreach (SmoDatabase database in available)
        {
            if ((LanguagePrimitives.IsTrue(Database) && !included.Matches(database.Name)) ||
                (LanguagePrimitives.IsTrue(ExcludeDatabase) && excluded.Matches(database.Name)))
                continue;
            if (database.IsAccessible)
                selected.Add(database);
            else
                WriteMessage(MessageLevel.Verbose, String.Format("{0} is not accessible on {1}, skipping", database, instance));
        }
        return selected;
    }

    // PS: -In compares each value, on the left, with the name, ignoring case.
    // Correction database-wildcards: the pinned help documents wildcards for both filters, which -In never honoured. Each
    // instance's own names decide which pattern values are real names and stay literal.
    private static WildcardNameMatcher NameMatcher(object[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true,
            (value, name) => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture), scope);
    }

    private static bool IsAzure(Server server) => server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;

    private void ReadFileSpaceUsage(Server server, List<SmoDatabase> databases)
    {
        foreach (SmoDatabase database in databases)
        {
            DataRow usage;
            try
            {
                usage = ReadUsage(server, database).Tables[0].Rows[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // Correction failed-read-row: the pin goes on to build this database's row from what the last read left.
                // Here the failed database gets no row and the next one is read.
                ReportFault(ServerQueryFaultRecord(failure));
                continue;
            }

            // PS: [math]::Round on the decimal the query returns.
            decimal changed = (decimal)LanguagePrimitives.ConvertTo(usage["ChangedPerc"], typeof(decimal), CultureInfo.InvariantCulture);
            WriteObject(NewRow(server, database.Name, usage["ExtentsTotal"], usage["ExtentsChanged"], Math.Round(changed, 2)));
        }
    }

    // PS: the database is named in the query rather than run in it, which would leave the caller's connection there (#10555).
    // Azure SQL Database refuses another database's name and has no USE, so there the database's own connection runs it.
    private static DataSet ReadUsage(Server server, SmoDatabase database)
    {
        if (IsAzure(server))
            return database.ExecuteWithResults(String.Format(FileSpaceUsageSql, String.Empty));
        return server.ConnectionContext.ExecuteWithResults(String.Format(FileSpaceUsageSql, "[" + database.Name.Replace("]", "]]") + "]."));
    }

    private void ReadBitmaps(Server server, List<SmoDatabase> databases)
    {
        List<KeyValuePair<string, List<DataRow>>> groups;
        try
        {
            groups = ReadMasterFiles(server, databases.ConvertAll(item => item.Name));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // Correction failed-read-row: no row for this instance, and the next instance is read.
            ReportFault(ServerQueryFaultRecord(failure));
            return;
        }

        foreach (KeyValuePair<string, List<DataRow>> group in groups)
        {
            PSObject row;
            try
            {
                row = ReadPages(server, group.Key, group.Value);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // Correction failed-read-row: no row for this database, and the next one is read.
                ReportFault(ServerQueryFaultRecord(failure));
                continue;
            }
            WriteObject(row);
        }
    }

    // These two are static so a native test can run them: every instance in the lab is new enough to take the view.
    // PS: master_files, Where-Object dbname -In $sourcedbs.Name, Group-Object -Property dbname.
    private static List<KeyValuePair<string, List<DataRow>>> ReadMasterFiles(Server server, List<string> names)
    {
        List<KeyValuePair<string, List<DataRow>>> groups = new();
        foreach (DataRow file in server.ConnectionContext.ExecuteWithResults(MasterFilesSql).Tables[0].Rows)
        {
            string? name = file["dbname"] as string;
            if (name is null || !names.Exists(item => String.Equals(item, name, StringComparison.OrdinalIgnoreCase)))
                continue;
            int group = groups.FindIndex(item => String.Equals(item.Key, name, StringComparison.OrdinalIgnoreCase));
            if (group < 0)
                groups.Add(new KeyValuePair<string, List<DataRow>>(name, new List<DataRow> { file }));
            else
                groups[group].Value.Add(file);
        }
        return groups;
    }

    // PS: one DBCC PAGE per differential bitmap, the first at page 6 and then one every 511232 pages.
    private static PSObject ReadPages(Server server, string name, List<DataRow> files)
    {
        object sizeTotal = 0;
        List<string> changed = new();
        foreach (DataRow file in files)
        {
            int size = Convert.ToInt32(file["size"], CultureInfo.InvariantCulture);
            sizeTotal = PsAdd(sizeTotal, PsDivide(size, 8));
            for (long extentId = 0; extentId < size; extentId += 511232)
            {
                string sql = String.Format(CultureInfo.InvariantCulture, PageSql, file["database_id"], file["file_id"], extentId + 6);
                foreach (DataRow row in server.ConnectionContext.ExecuteWithResults(sql).Tables[0].Rows)
                {
                    if (String.Equals(row["VALUE"] as string, "    CHANGED", StringComparison.OrdinalIgnoreCase) &&
                        (row["ParentObject"] as string ?? String.Empty).StartsWith("DIFF_MAP", StringComparison.OrdinalIgnoreCase))
                        changed.Add(row["Field"] as string ?? String.Empty);
                }
            }
        }

        object extents = CountExtents(changed);
        double percent = Convert.ToDouble(extents, CultureInfo.InvariantCulture) / Convert.ToDouble(sizeTotal, CultureInfo.InvariantCulture) * 100;
        return NewRow(server, name, sizeTotal, extents, Math.Round(percent, 2));
    }

    // PS: Get-DbaExtent. A field names one extent or a range of them; a field with neither reads as 0 to 0.
    private static object CountExtents(List<string> fields)
    {
        object result = 0;
        foreach (string field in fields)
        {
            MatchCollection extents = ExtentPattern.Matches(field);
            if (extents.Count == 1)
            {
                result = PsAdd(result, 1);
                continue;
            }
            int first = extents.Count > 0 ? Int32.Parse(extents[0].Groups["extent"].Value, CultureInfo.InvariantCulture) : 0;
            int last = extents.Count > 1 ? Int32.Parse(extents[1].Groups["extent"].Value, CultureInfo.InvariantCulture) : 0;
            result = PsAdd(result, PsAdd(PsDivide(last - first, 8), 1));
        }
        return result;
    }

    // PS: / stays an integer when the division is exact, and a double otherwise.
    private static object PsDivide(int dividend, int divisor)
    {
        if (dividend % divisor == 0)
            return dividend / divisor;
        return (double)dividend / divisor;
    }

    // PS: + keeps integers until they overflow, and doubles once either side is one.
    private static object PsAdd(object left, object right)
    {
        if (left is int first && right is int second)
        {
            long sum = (long)first + second;
            if (sum >= Int32.MinValue && sum <= Int32.MaxValue)
                return (int)sum;
            return (double)sum;
        }
        return Convert.ToDouble(left, CultureInfo.InvariantCulture) + Convert.ToDouble(right, CultureInfo.InvariantCulture);
    }

    private static PSObject NewRow(Server server, string name, object? total, object? changed, object percent)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("DatabaseName", name));
        output.Properties.Add(new PSNoteProperty("ExtentsTotal", total));
        output.Properties.Add(new PSNoteProperty("ExtentsChanged", changed));
        output.Properties.Add(new PSNoteProperty("ChangedPerc", percent));
        return output;
    }

    // A failed $server.Query is a statement of the pin's process block with no try around it: a plain call writes the record
    // and goes on, and a caller's try catches it and the command goes no further. -EnableException stops here (the keep-going
    // section's point 3; the pin's raw fault ignores that switch); -ErrorAction Stop has the effect PowerShell gives WriteError.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        StatementFault.Surface(this, fault);
    }

    // The record of a failed Server.Query, whose catch joins the messages of the failure's exception chain and throws that text.
    private static ErrorRecord ServerQueryFaultRecord(Exception failure)
    {
        string message = String.Empty;
        Exception current = failure;
        while (current.InnerException is not null)
        {
            message += current.Message;
            current = current.InnerException;
        }
        message += current.Message;
        MethodInvocationException call = new(String.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
