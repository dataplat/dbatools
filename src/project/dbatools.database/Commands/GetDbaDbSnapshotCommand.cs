#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves database snapshots and their disk usage directly through SMO (port of public/Get-DbaDbSnapshot.ps1).
/// <summary>Retrieves database snapshots with their source databases, creation times, and disk usage</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbSnapshot")]
public sealed class GetDbaDbSnapshotCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL 2005+).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Filter to snapshots of the specified base database(s).</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Exclude snapshots of the specified base database(s).</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Filter to the specified snapshot(s) by name.</summary>
    [Parameter(Position = 4)]
    public object[]? Snapshot { get; set; }

    /// <summary>Exclude the specified snapshot(s) by name.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeSnapshot { get; set; }

    private const string DiskUsageSql = "SELECT SUM(BytesOnDisk) AS BytesOnDisk FROM fn_virtualfilestats(DB_ID(),NULL) S JOIN sys.databases D ON D.database_id = S.dbid";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null)
                continue;

            foreach (SmoDatabase database in SelectSnapshots(server))
            {
                if (Interrupted)
                    return;
                try
                {
                    object? bytesOnDisk = QueryBytesOnDisk(server, database);
                    PSObject result = PSObject.AsPSObject(database);
                    // Add-Member -Force replaces notes left on the same SMO object by an earlier call.
                    foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "DiskUsage", "SnapshotOf" })
                        result.Properties.Remove(property);
                    OutputHelper.AddInstanceProperties(result, server);
                    // PS: [dbasize]($BytesOnDisk.BytesOnDisk) - the script cast, null for no row.
                    result.Properties.Add(new PSNoteProperty("DiskUsage",
                        LanguagePrimitives.ConvertTo(bytesOnDisk, typeof(Size), CultureInfo.InvariantCulture)));
                    // Select-DefaultView 'DatabaseSnapshotBaseName as SnapshotOf'
                    OutputHelper.AddAliasProperty(result, "SnapshotOf", "DatabaseSnapshotBaseName");
                    OutputHelper.SetDefaultDisplayPropertySet(result,
                        "ComputerName", "InstanceName", "SqlInstance", "Name", "SnapshotOf", "CreateDate", "DiskUsage");
                    WriteObject(result);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue
                    StopFunction("Failure", target: database, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                    continue;
                }
            }
        }
    }

    /// <summary>The source's Where-Object/Sort-Object chain, materialized before any query runs.</summary>
    private List<SmoDatabase> SelectSnapshots(Server server)
    {
        bool hasDatabase = LanguagePrimitives.IsTrue(Database);
        bool hasSnapshot = LanguagePrimitives.IsTrue(Snapshot);
        List<SmoDatabase> selected = new();
        foreach (SmoDatabase candidate in server.Databases)
        {
            string baseName = candidate.DatabaseSnapshotBaseName;
            if (!LanguagePrimitives.IsTrue(baseName))
                continue;
            // PS: $Database -contains $_.DatabaseSnapshotBaseName - each supplied value is the left operand.
            if (hasDatabase && !NativeDatabaseSelection.ContainsInOperand(Database, baseName))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, baseName))
                continue;
            if (hasSnapshot && !NativeDatabaseSelection.ContainsInOperand(Snapshot, candidate.Name))
                continue;
            if (!hasSnapshot && !hasDatabase && !candidate.IsDatabaseSnapshot)
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeSnapshot) && NativeDatabaseSelection.ContainsInOperand(ExcludeSnapshot, candidate.Name))
                continue;
            selected.Add(candidate);
        }
        if (hasSnapshot || hasDatabase)
            return selected;

        // Sort-Object DatabaseSnapshotBaseName, Name: current culture, case-insensitive, stable.
        CompareInfo compare = CultureInfo.CurrentCulture.CompareInfo;
        Comparer<string> byText = Comparer<string>.Create((first, second) => compare.Compare(first, second, CompareOptions.IgnoreCase));
        return selected
            .OrderBy(database => database.DatabaseSnapshotBaseName, byText)
            .ThenBy(database => database.Name, byText)
            .ToList();
    }

    /// <summary>
    /// PS: $db.Query($sql, $db.Name).BytesOnDisk through the Database.Query script method of
    /// xml/dbatools.Types.ps1xml: the truthy second argument returns every table, whose rows member
    /// enumeration then reads, and the caller's previous database context is put back afterwards.
    /// </summary>
    private object? QueryBytesOnDisk(Server server, SmoDatabase database)
    {
        ServerConnection connection = server.ConnectionContext;
        SetActiveConnection(connection);
        string previous = connection.CurrentDatabase;
        DataSet results;
        try
        {
            results = database.ExecuteWithResults(DiskUsageSql);
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            throw new QueryFault(error);
        }
        finally
        {
            RestoreDatabaseContext(connection, previous);
        }

        List<object?> values = new();
        foreach (DataTable table in results.Tables)
        {
            if (!table.Columns.Contains("BytesOnDisk"))
                continue;
            foreach (DataRow row in table.Rows)
                values.Add(row["BytesOnDisk"]);
        }
        if (values.Count == 0)
            return null;
        return values.Count == 1 ? values[0] : values.ToArray();
    }

    private void RestoreDatabaseContext(ServerConnection connection, string previous)
    {
        // Case-sensitive on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(previous) || String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + previous.Replace("]", "]]") + "]");
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // Restoring the context is housekeeping and never becomes the outcome of the query.
            string text = String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                previous, error.Message);
            try
            {
                WriteWarning(text); // style-ok: cs-raw-streams the source script method calls plain Write-Warning, not Write-Message
            }
            catch (ActionPreferenceStopException)
            {
                // The source forces this one warning to Continue, so a Stop preference must not end the command here.
            }
        }
    }

    /// <summary>PS: catch { Stop-Function ... -ErrorRecord $_ } - the record the script catch saw.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is QueryFault fault)
        {
            // The .NET call inside the script method fails as 'Exception calling "ExecuteWithResults"', and the
            // engine reports the script method's failure as the ScriptMethodRuntimeException of "Query" with two arguments.
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", fault.InnerException!.Message), fault.InnerException);
            MethodInvocationException method = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"2\" argument(s): \"{0}\"", call.Message), call);
            return new ErrorRecord(method, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }
        ErrorRecord? inner = (ex as IContainsErrorRecord)?.ErrorRecord;
        if (inner is not null)
            return inner;
        return new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>Marks a failure of the Database.Query call so the caught record carries its script-method identity.</summary>
    private sealed class QueryFault : Exception
    {
        internal QueryFault(Exception inner) : base(inner.Message, inner)
        {
        }
    }
}
