#nullable enable

using System;
using System.Data;
using System.IO;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Retrieves the default data, log, backup and error log paths of SQL Server instances.
// Port of public/Get-DbaDefaultPath.ps1; surface pinned by migration/baselines/Get-DbaDefaultPath.json.
/// <summary>Retrieves default file paths for SQL Server data, log, backup, and error log directories</summary>
[Cmdlet(VerbsCommon.Get, "DbaDefaultPath")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaDefaultPathCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -AzureUnsupported } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            object? dataPath = server.DefaultFile;
            if (HasZeroLength(dataPath))
            {
                // PS: $server.Query("SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS Data").Data
                dataPath = QueryColumn(server, "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS Data", "Data");
            }

            if (dataPath == DBNull.Value || HasZeroLength(dataPath))
            {
                // PS: Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).FileGroups[0].Files[0].FileName
                // Get-DbaDatabase hands back the same SMO object as $server.Databases["model"].
                dataPath = Path.GetDirectoryName(server.Databases["model"].FileGroups[0].Files[0].FileName);
            }

            if (HasZeroLength(dataPath))
            {
                dataPath = server.Information.MasterDBPath;
            }

            object? logPath = server.DefaultLog;

            if (HasZeroLength(logPath))
            {
                // PS: $server.Query("SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS Log").Log
                logPath = QueryColumn(server, "SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS Log", "Log");
            }

            if (logPath == DBNull.Value || HasZeroLength(logPath))
            {
                // PS: Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).LogFiles.FileName
                logPath = LogFileDirectories(server.Databases["model"].LogFiles);
            }

            if (HasZeroLength(logPath))
            {
                logPath = server.Information.MasterDBLogPath;
            }

            // PS: $dataPath = $dataPath.Trim().TrimEnd("\"); then the same for $logPath.
            object? data = TrimPath(dataPath);
            object? log = TrimPath(logPath);

            PSObject result = new();
            OutputHelper.AddInstanceProperties(result, server);
            result.Properties.Add(new PSNoteProperty("Data", data));
            result.Properties.Add(new PSNoteProperty("Log", log));
            result.Properties.Add(new PSNoteProperty("Backup", server.BackupDirectory));
            result.Properties.Add(new PSNoteProperty("ErrorLog", server.ErrorLogPath));

            // The PS source emits the bare PSCustomObject with no Select-DefaultView call,
            // so no display set is attached here either.
            WriteObject(result);
        }
    }

    /// <summary>
    /// PS: $value.Length -eq 0 without strict mode. $null.Length is 0, so null takes the
    /// fallback; a string or array compares its own length; DBNull and other scalars report
    /// the intrinsic Length 1 and do not (measured on Windows PowerShell 5.1 and PowerShell 7).
    /// </summary>
    private static bool HasZeroLength(object? value)
    {
        return value switch
        {
            null => true,
            string text => text.Length == 0,
            object?[] items => items.Length == 0,
            _ => false,
        };
    }

    /// <summary>
    /// PS: Split-Path over the member-enumerated LogFiles.FileName. One log file yields its
    /// directory; several yield one directory per file, collected as an array, as the
    /// pipeline does. Path.GetDirectoryName matches Split-Path once the trailing separator
    /// is trimmed below.
    /// </summary>
    private static object? LogFileDirectories(LogFileCollection logFiles)
    {
        if (logFiles.Count == 1)
        {
            return Path.GetDirectoryName(logFiles[0].FileName);
        }

        object?[] directories = new object?[logFiles.Count];
        for (int i = 0; i < logFiles.Count; i++)
        {
            directories[i] = Path.GetDirectoryName(logFiles[i].FileName);
        }
        return directories;
    }

    /// <summary>
    /// PS: $path.Trim().TrimEnd("\"); member enumeration applies it to every element of an
    /// array. A null path faults as $null.Trim() does, with the engine's InvokeMethodOnNull record.
    /// </summary>
    private object? TrimPath(object? path)
    {
        if (path is null)
        {
            // $null.Trim() is a statement fault outside any try in the source, so whether it ends the
            // command or only the assignment depends on the caller's try/trap, which a cmdlet cannot observe.
            // caller-try: terminate -- the source only reaches here when every default-path lookup came back empty; continuing would emit a row without the path the command exists to report
            RuntimeException nullFailure = new("You cannot call a method on a null-valued expression.");
            ThrowTerminatingError(new ErrorRecord(nullFailure, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
            return null;
        }

        if (path is object?[] items)
        {
            object?[] trimmed = new object?[items.Length];
            for (int i = 0; i < items.Length; i++)
            {
                trimmed[i] = Convert.ToString(items[i])?.Trim().TrimEnd('\\');
            }
            return trimmed;
        }

        return Convert.ToString(path)!.Trim().TrimEnd('\\');
    }

    /// <summary>
    /// PS: $server.Query($sql).$column. The Server.Query script method runs
    /// ConnectionContext.ExecuteWithResults and returns the first table; the property read
    /// enumerates its single row.
    /// </summary>
    private object? QueryColumn(Server server, string sql, string columnName)
    {
        DataSet resultSet;
        try
        {
            resultSet = server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure)
        {
            // No try encloses the Query call in the source, so whether its fault ends the command or
            // only the assignment depends on the caller's try/trap, which a cmdlet cannot observe.
            // caller-try: terminate -- continuing would present the model-file fallback as the default path after the configured lookup failed
            ThrowTerminatingError(new ErrorRecord(QueryMethodException(failure), "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
            return null;
        }

        if (resultSet.Tables.Count == 0 || resultSet.Tables[0].Rows.Count == 0)
        {
            return null;
        }
        return resultSet.Tables[0].Rows[0][columnName];
    }

    /// <summary>
    /// Rebuilds the error of the Server.Query script method: its catch concatenates the messages
    /// of the failed call's exception chain without separators and throws that string; the
    /// method binder wraps the throw as 'Exception calling "Query" with "1" argument(s): "message"'.
    /// The original failure stays reachable as the inner exception's InnerException.
    /// </summary>
    private static MethodInvocationException QueryMethodException(Exception failure)
    {
        return NativeServerQuery.QueryMethodException(failure);
    }
}
