#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbPageInfo.ps1 at refs/pins/dbatools-2026-10-22.
/// <summary>Retrieves detailed page allocation information from SQL Server databases for storage analysis and troubleshooting</summary>
/// <para>
/// This function queries the sys.dm_db_database_page_allocations dynamic management view to return detailed information about page allocation, including page type, free space percentage, allocation status, and mixed page allocation indicators.
/// Use this when troubleshooting storage issues, analyzing space utilization patterns, or investigating page-level performance problems in your databases.
/// Results can be filtered by specific databases, schemas, and tables to focus your analysis on problem areas.
/// Requires SQL Server 2012 or higher as it depends on the sys.dm_db_database_page_allocations DMV.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbPageInfo -SqlInstance sql2017
/// </code>
/// <para>
/// Returns page information for all databases on sql2017
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbPageInfo -SqlInstance sql2017, sql2016 -Database testdb
/// </code>
/// <para>
/// Returns page information for the testdb on sql2017 and sql2016
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers | Get-DbaDatabase -Database testdb | Get-DbaDbPageInfo
/// </code>
/// <para>
/// Returns page information for the testdb on all $servers
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Database, Page
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
/// <seealso href="https://dbatools.io/Get-DbaDbPageInfo" />
[Cmdlet(VerbsCommon.Get, "DbaDbPageInfo")]
public sealed class GetDbaDbPageInfoCommand : DbaInstanceCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every non-switch parameter in order.

    /// <para>
    /// The target SQL Server instance or instances
    /// </para>
    [Parameter(Position = 0)]
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
    /// Specifies which databases to analyze for page allocation information. Accepts wildcards for pattern matching.
    /// Use this when you need to focus on specific databases rather than scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Limits the analysis to tables within specific schemas only. Multiple schema names can be provided.
    /// Helpful when troubleshooting page issues in specific application schemas or when you want to exclude system schemas from results.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <para>
    /// Restricts page information retrieval to specific tables only. Can be combined with Schema parameter for precise targeting.
    /// Use this when investigating page allocation problems for known problematic tables or when performing focused storage analysis.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <para>
    /// Accepts database objects piped from Get-DbaDatabase, allowing you to chain commands together.
    /// This enables scenarios like getting databases from multiple instances and then analyzing their page information in a single pipeline.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public SmoDatabase[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string PageQuery = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, [Database] = DB_NAME(DB_ID()),
        ss.name AS [Schema], st.name AS [Table], dbpa.page_type_desc AS PageType,
                        dbpa.page_free_space_percent AS PageFreePercent,
                        IsAllocated =
                          CASE dbpa.is_allocated
                             WHEN 0 THEN 'False'
                             WHEN 1 THEN 'True'
                          END,
                        IsMixedPage =
                          CASE dbpa.is_mixed_page_allocation
                             WHEN 0 THEN 'False'
                             WHEN 1 THEN 'True'
                          END
                        FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS dbpa
                        INNER JOIN sys.tables AS st ON st.object_id = dbpa.object_id
                        INNER JOIN sys.schemas AS ss ON ss.schema_id = st.schema_id";

    private const string QueryFailure = "Something went wrong executing the query";
    private const string UnsupportedVersion = "Unsupported SQL Server version";

    private string _statement = PageQuery;
    private bool _instancesRead;
    private bool _instanceAssigned;
    private DbaInstanceParameter? _lastInstance;

    /// <summary>Builds the one statement every database runs, as the begin block does.</summary>
    protected override void BeginProcessing()
    {
        bool schemaFilter = LanguagePrimitives.IsTrue(Schema);
        // Correction schema-unicode-literals: every name is a Unicode literal, where the pin gives only the first its N prefix and the
        // engine turns the others into the database's code page, so a schema outside it silently returned nothing.
        if (schemaFilter)
            _statement += " WHERE ss.name IN (" + String.Join(",", Array.ConvertAll(Schema!, name => UnicodeLiteral(name ?? ""))) + ")";

        if (LanguagePrimitives.IsTrue(Table))
        {
            List<string> clauses = new();
            foreach (string? table in Table!)
                clauses.Add(TableClause(table));
            string tableFilter = String.Join(" OR ", clauses);
            _statement += schemaFilter ? " AND (" + tableFilter + ")" : " WHERE " + tableFilter;
        }
    }

    /// <summary>Reads the pages of the record's piped databases, then those of -SqlInstance.</summary>
    protected override void ProcessRecord()
    {
        // PS: foreach ($instance in $SqlInstance) { $InputObject += $server.Databases ... }, before the first database is read.
        // Correction sqlinstance-read-once: a command-line -SqlInstance is read after the first record's piped databases and not
        // again, where the pin reads it for every piped record and repeats its rows.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (!_instancesRead)
        {
            _instancesRead = true;
            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                _instanceAssigned = true;
                _lastInstance = instance;
                Server? server = ConnectInstance(instance, "Failure", minimumVersion: 11);
                if (server is not null)
                    databases.AddRange(SelectDatabases(server));
            }
        }

        foreach (SmoDatabase? database in databases)
            ReadPages(database);
    }

    // PS: $server.Databases | Where-Object { $_.Name -in $Database }, in the collection's order; an empty -Database keeps them all.
    // Correction database-wildcards: the pinned help documents wildcards for -Database, which -in never honoured. Each instance's
    // own names decide which pattern values are real names and stay literal.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        List<SmoDatabase> available = new();
        foreach (SmoDatabase database in server.Databases)
            available.Add(database);
        if (!LanguagePrimitives.IsTrue(Database))
            return available;

        WildcardNameMatcher requested = WildcardNameFilter.CreateMatcher(Database, true,
            (value, name) => PsOps.In(name, new[] { value }), available.ConvertAll(item => item.Name));
        return available.FindAll(database => requested.Matches(database.Name));
    }

    private void ReadPages(SmoDatabase? database)
    {
        if (ServerVersion(database) is not >= 11)
        {
            ReportUnsupported(database);
            return;
        }

        DataTable pages;
        try
        {
            pages = QueryDatabase(database!);
        }
        catch (QueryFault fault)
        {
            ReportQueryFailure(fault.Record);
            return;
        }

        foreach (DataRow row in pages.Rows)
            WriteObject(row);
    }

    // PS: $db.Parent.VersionMajor. A null element reads null, and so does a getter that throws: an SMO database without a server
    // raises "You must set Parent property." from Parent, which the dot operator drops. Null -ge 11 is false.
    private static int? ServerVersion(SmoDatabase? database)
    {
        try
        {
            return database?.Parent?.VersionMajor;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: Stop-Function -Message "Unsupported SQL Server version" -Target $db -Continue inside the try. Under -EnableException its
    // throw lands in the function's own catch, whose Stop-Function reports that record as the query failure and stops the command.
    private void ReportUnsupported(SmoDatabase? database)
    {
        if (EnableException.ToBool())
        {
            ReportQueryFailure(CaughtNestedStopFunction("Get-DbaDbPageInfo", UnsupportedVersion, target: database));
            return;
        }
        StopFunction(UnsupportedVersion, target: database, continueLoop: true);
    }

    // PS: Stop-Function -Message "Something went wrong executing the query" -ErrorRecord $_ -Target $instance -Continue. $instance is
    // the last value of the instance loop; when that loop never assigned it, the name resolves past the function to the dbatools
    // module scope, which does not define it, and then the global scope.
    private void ReportQueryFailure(ErrorRecord record)
    {
        object? target = _instanceAssigned ? _lastInstance : SessionState.PSVariable.GetValue("global:instance");
        StopFunction(QueryFailure, target: target, errorRecord: record, continueLoop: true);
    }

    // PS: $db.Query($sql), the pinned Database.Query script method: ExecuteWithResults on the parent's connection, its first table,
    // and in its finally the connection put back in the database it was in.
    private DataTable QueryDatabase(SmoDatabase database)
    {
        ServerConnection connection = database.Parent.ConnectionContext;
        SetActiveConnection(connection);
        string? previous = ContextDatabase(connection);
        try
        {
            return database.ExecuteWithResults(_statement).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            throw new QueryFault(new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        finally
        {
            // -cne in the script method: database names follow the instance collation.
            if (!String.IsNullOrEmpty(previous) && !String.Equals(ContextDatabase(connection), previous, StringComparison.Ordinal))
                PutBack(connection, previous!);
        }
    }

    // PS: the script method's catch around the USE writes "The database context could not be restored to [<database>]: <message>"
    // with a plain Write-Warning, and raises a Stop, Inquire or Ignore preference to Continue for that one call. The port writes the
    // same text with the command's own WriteWarning and leaves the preference to the engine, as for any compiled cmdlet ("Database-context
    // restore warning: ports follow the compiled cmdlet's warning preference (operator, 2026-11-15)", point 1): Stop ends the call
    // here, Inquire and -Debug ask, and Ignore drops it. What the write raises goes up to the engine.
    private void PutBack(ServerConnection connection, string previous)
    {
        try
        {
            connection.ExecuteNonQuery("USE [" + previous.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string text = String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                previous, failure.Message);
            WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
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

    // PS: the table's own clause from Get-ObjectNameParts. A name that does not split has no parts and matches no table.
    private static string TableClause(string? table)
    {
        ObjectNameParser.Split(table ?? "", out string? database, out string? schema, out string? name);
        List<string> parts = new() { "st.name = " + UnicodeLiteral(name ?? "") };
        if (!String.IsNullOrEmpty(schema))
            parts.Add("ss.name = " + UnicodeLiteral(schema!));
        if (!String.IsNullOrEmpty(database))
            parts.Add("DB_NAME() = " + UnicodeLiteral(database!));
        return "(" + String.Join(" AND ", parts) + ")";
    }

    private static string UnicodeLiteral(string value)
    {
        return "N'" + value.Replace("'", "''") + "'";
    }

    /// <summary>A failed $db.Query, carrying the record the script method raises.</summary>
    private sealed class QueryFault : Exception
    {
        internal QueryFault(ErrorRecord record) : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
