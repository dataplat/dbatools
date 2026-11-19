#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Port of private/functions/Get-XpDirTreeRestoreFile.ps1: gets SQL Server backfiles from a
/// specified folder using xp_dirtree. Takes path, checks for validity. Scans for usual
/// backup file. Returns objects carrying a FullName property, like the PS Select-Object
/// projection did.
/// </summary>
internal static class XpDirTreeScanner
{
    /// <summary>
    /// The scan. The PS function's Connect-DbaInstance call is a live-SMO pass-through at
    /// every call site (the caller always hands over its connected $server), so the port
    /// accepts the Server directly. Stop-Function sites replicate the PS shapes exactly —
    /// including the sites that deliberately fall through without a return.
    /// </summary>
    internal static List<PSObject> Scan(PSCmdlet host, Server server, string path, bool noRecurse, bool enableException)
    {
        const string functionName = "Get-XpDirTreeRestoreFile";

        InnerCommand.Message(host, functionName, enableException, MessageLevel.InternalComment, "Starting");

        // Determine the correct path separator based on whether this is a URL or file system path
        // PS -match is case-insensitive (cross-model review 2026-07-07 finding A3).
        string? pathSep;
        if (System.Text.RegularExpressions.Regex.IsMatch(path, "^https?://", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
        {
            pathSep = "/";
        }
        else if (System.Text.RegularExpressions.Regex.IsMatch(path, "^s3://", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
        {
            // S3 paths cannot be enumerated via T-SQL (xp_dirtree/dm_os_enumerate_filesystem don't support S3)
            // SQL Server 2022+ supports S3 for BACKUP/RESTORE but has no built-in function to list S3 objects
            // Return empty array - caller should handle S3 enumeration in PowerShell or use explicit file paths
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning, "S3 paths cannot be enumerated using T-SQL. Use explicit file paths or PowerShell-based enumeration for S3 storage.");
            InnerCommand.Stop(host, functionName, enableException, $"S3 path enumeration not supported. Path: {path}");
            // PS source has no return after this Stop-Function: execution falls through with no
            // path separator, exactly like the function scope did.
            pathSep = null;
        }
        else
        {
            pathSep = RestoreUtility.GetPathSep(server);
        }

        if (path.EndsWith(".bak", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".trn", StringComparison.OrdinalIgnoreCase))
        {
            // For a future person who knows what's up, please replace this comment with the reason this is empty
        }
        else if (pathSep is not null && !path.EndsWith(pathSep, StringComparison.Ordinal))
        {
            path += pathSep;
        }

        // The PS source runs the identical Test-DbaPath check twice back to back; both are kept.
        if (!TestPathTruthy(host, server, path))
            InnerCommand.Stop(host, functionName, enableException, $"SqlInstance {server.Name} cannot access {path}");
        if (!TestPathTruthy(host, server, path))
            InnerCommand.Stop(host, functionName, enableException, $"SqlInstance {server.Name} cannot access {path}");

        string sql;
        if (server.VersionMajor >= 14)
        {
            // this is all kinds of cool, api could be expanded sooo much here
            sql = @"SELECT file_or_directory_name AS subdirectory, ~CONVERT(BIT, is_directory) AS [file], 1 AS depth
        FROM sys.dm_os_enumerate_filesystem(@path, '*')
        WHERE [level] = 0";
        }
        else if (server.VersionMajor < 9)
        {
            sql = "EXEC master..xp_dirtree @path,1,1;";
        }
        else
        {
            sql = "EXEC master.sys.xp_dirtree @path,1,1;";
        }

        // BP-101: the path is a user-supplied value, so it binds as a typed SqlParameter
        // instead of the PS source's string interpolation. Semantic parity; the emitted text
        // differs from the PS original by design.
        DataTable queryResult = new();
        SqlConnection connection = server.ConnectionContext.SqlConnectionObject;
        if (connection.State != ConnectionState.Open)
            connection.Open();
        using (SqlCommand command = new(sql, connection))
        {
            command.CommandTimeout = server.ConnectionContext.StatementTimeout;
            command.Parameters.Add(new SqlParameter("@path", System.Data.SqlDbType.NVarChar, 4000) { Value = path });
            using SqlDataReader reader = command.ExecuteReader();
            queryResult.Load(reader);
        }
        InnerCommand.Message(host, functionName, enableException, MessageLevel.Debug, sql);

        List<DataRow> dirs = new();
        List<PSObject> results = new();
        foreach (DataRow row in queryResult.Rows)
        {
            object fileFlagRaw = row["file"];
            if (fileFlagRaw is DBNull)
                continue;
            int fileFlag = Convert.ToInt32(fileFlagRaw, System.Globalization.CultureInfo.InvariantCulture);
            if (fileFlag == 0)
            {
                dirs.Add(row);
            }
            else if (fileFlag == 1)
            {
                PSObject entry = new();
                entry.Properties.Add(new PSNoteProperty("FullName", path + RestoreUtility.PsStringify(row["subdirectory"] is DBNull ? null : row["subdirectory"])));
                results.Add(entry);
            }
        }

        if (!noRecurse)
        {
            foreach (DataRow d in dirs)
            {
                string fullpath = path + RestoreUtility.PsStringify(d["subdirectory"] is DBNull ? null : d["subdirectory"]);
                InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose, $"Enumerating subdirectory '{fullpath}'");
                // PS recursion drops both -EnableException and -NoRecurse, so deeper levels
                // warn instead of throwing and always keep recursing. Preserved.
                results.AddRange(Scan(host, server, fullpath, noRecurse: false, enableException: false));
            }
        }
        return results;
    }

    private static bool TestPathTruthy(PSCmdlet host, Server server, string path)
    {
        Hashtable parameters = new()
        {
            ["SqlInstance"] = server,
            ["Path"] = path
        };
        var result = NestedCommand.Invoke(host, "Test-DbaPath", parameters);
        if (result.Count == 0)
            return false;
        return LanguagePrimitives.IsTrue(result.Count == 1 ? result[0] : result);
    }
}
