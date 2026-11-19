#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>The rows and Add-Member notes of Get-DbaDatabase that ports read through a database's parent; each command keeps its own selection.</summary>
internal static class NativeDatabaseNotes
{
    private const string DatabaseCommand = "Get-DbaDatabase";

    // PS: Invoke-QueryRawDatabases, whose text keeps the rows in the order the pin reads them.
    internal const string InstanceDatabasesQuery = "SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases";
    internal const string AzureDatabasesQuery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid";

    // PS: $querySizes of Get-DbaDatabase, which stands in for a Size that SMO reports as null or 0. Azure SQL Database has no sys.master_files, so each database is asked itself.
    private const string InstanceSizesQuery = "SELECT DB_NAME(database_id) AS name, CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB FROM sys.master_files GROUP BY database_id";
    private const string AzureSizeQuery = "SELECT DB_NAME() AS name, CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB FROM sys.database_files";

    // PS: the Add-Member calls of Get-DbaDatabase in its order, which callers read through $user.Parent. This call gives it neither -NoFullBackup nor -IncludeLastUsed, so
    // BackupStatus, LastRead and LastWrite are present and null. The Azure query has no is_cdc_enabled column, so IsCdcEnabled is null there.
    internal static void AddDatabaseNotes(Server server, SmoDatabase database, DataRow row, DataTable? sizes, bool azure)
    {
        PSObject output = PSObject.AsPSObject(database);
        string name = RowName(row);
        object? size = ReadSize(output);
        if (size is null || LanguagePrimitives.Equals(size, 0))
            size = (azure ? ReadAzureSize(server, name) : ListedSize(sizes, name)) ?? size;

        SetNote(output, "BackupStatus", null);
        AddInstanceNotes(output, server);
        SetNote(output, "LastRead", null);
        SetNote(output, "LastWrite", null);
        SetNote(output, "IsCdcEnabled", row.Table.Columns.Contains("is_cdc_enabled") ? row["is_cdc_enabled"] : null);
        if (size is not null)
            SetNote(output, "Size", size);
    }

    private static void SetNote(PSObject output, string name, object? value)
    {
        output.Properties.Remove(name);
        output.Properties.Add(new PSNoteProperty(name, value));
    }

    // PS: $db.Size; a getter that fails reads as $null.
    private static object? ReadSize(PSObject output)
    {
        try
        {
            return output.Properties["Size"]?.Value;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: Invoke-QueryDatabaseSizes; a failure warns and leaves every Size as SMO reports it.
    // The message carries the fields of DbaBaseCmdlet.WriteAttributedMessage, which is protected and so cannot be called from here.
    internal static DataTable? ReadInstanceSizes(DbaBaseCmdlet caller, Server server)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(InstanceSizesQuery).Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string joined = "";
            for (Exception? inner = failure; inner is not null; inner = inner.InnerException)
                joined += inner.Message;
            MessageService.Write(caller, new MessageService.MessageRequest
            {
                FunctionName = DatabaseCommand, ModuleName = "dbatools", Level = MessageLevel.Warning,
                Message = "Could not retrieve database sizes via T-SQL: Exception calling \"Query\" with \"1\" argument(s): \"" + joined + "\"",
                EnableException = caller.EnableException.ToBool(),
                File = caller.MyInvocation.ScriptName, Line = caller.MyInvocation.ScriptLineNumber
            });
            return null;
        }
    }

    // PS: $dbSizes | Where-Object { $_.name -eq $db.Name }, then its SizeMB.
    private static object? ListedSize(DataTable? sizes, string name)
    {
        foreach (DataRow row in sizes?.Rows.Cast<DataRow>() ?? Enumerable.Empty<DataRow>())
        {
            if (LanguagePrimitives.Equals(row["name"], name, true, CultureInfo.InvariantCulture))
                return row["SizeMB"] is DBNull ? null : row["SizeMB"];
        }
        return null;
    }

    // PS: Invoke-DbaQuery -Database $db.Name -Query $querySizes -EnableException inside a catch that skips the database with no message. It runs here only for a database whose
    // Size SMO reports as null or 0, the only one whose note it changes.
    private static object? ReadAzureSize(Server server, string name)
    {
        ServerConnection? connection = null;
        try
        {
            ServerConnection copy = server.ConnectionContext.Copy();
            copy.NonPooledConnection = true;
            connection = copy.GetDatabaseConnection(name, false);
            return ListedSize(connection.ExecuteWithResults(AzureSizeQuery).Tables[0], name);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
        finally
        {
            if (connection is not null && connection.IsOpen)
                connection.Disconnect();
        }
    }

    internal static void AddInstanceNotes(PSObject target, Server server)
    {
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            target.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(target, server);
    }

    internal static string RowName(DataRow row)
    {
        return Convert.ToString(row["name"], CultureInfo.InvariantCulture) ?? String.Empty;
    }
}
