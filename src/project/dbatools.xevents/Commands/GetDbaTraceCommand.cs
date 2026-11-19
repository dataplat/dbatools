#nullable enable

using System;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Trace definitions from sys.traces.
/// Port of public/Get-DbaTrace.ps1; surface pinned by migration/baselines/Get-DbaTrace.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaTrace")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaTraceCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Returns only the traces with the given ids.</summary>
    [Parameter(Position = 2)]
    public int[]? Id { get; set; }

    /// <summary>Returns only the default system trace.</summary>
    [Parameter]
    public SwitchParameter Default { get; set; }

    private string _sql = "";

    protected override void BeginProcessing()
    {
        // A Microsoft.SqlServer.Management.Trace.TraceServer class exists but is buggy
        // and requires x86 PowerShell. So we'll go with T-SQL.
        _sql = "SELECT id, status, path, max_size, stop_time, max_files, is_rowset, is_rollover, is_shutdown, is_default, buffer_count, buffer_size, file_position, reader_spid, start_time, last_event_time, event_count, dropped_event_count FROM sys.traces";

        if (FilterHelper.IsActive(Id))
        {
            string idstring = string.Join(",", Array.ConvertAll(Id!, i => i.ToString(System.Globalization.CultureInfo.InvariantCulture)));
            _sql = _sql + " WHERE id IN (" + idstring + ")";
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
            {
                continue;
            }

            DataTable results;
            try
            {
                results = server.ConnectionContext.ExecuteWithResults(_sql).Tables[0];
            }
            catch (Exception ex)
            {
                // The PS source carries no -Continue here and never re-checks the interrupt
                // sentinel, so execution effectively moves to the next instance; continueLoop
                // mirrors that observable behavior.
                StopFunction(string.Format("Issue collecting trace data on {0}", server), target: server, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaTrace", ErrorCategory.NotSpecified, server), continueLoop: true);
                continue;
            }

            foreach (DataRow row in results.Rows)
            {
                if (Default.ToBool() && !ToBool(row["is_default"]))
                {
                    continue;
                }

                object? remotefile = null;
                if (row["path"] is not DBNull && row["path"].ToString()!.Length > 0)
                {
                    remotefile = JoinAdminUnc(SmoServerExtensions.GetComputerName(server), row["path"].ToString()!);
                }

                PSObject result = new();
                result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server)));
                result.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
                result.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server)));
                result.Properties.Add(new PSNoteProperty("Id", row["id"]));
                result.Properties.Add(new PSNoteProperty("Status", row["status"]));
                result.Properties.Add(new PSNoteProperty("IsRunning", ToBool(row["status"]) && Convert.ToInt32(row["status"]) == 1));
                result.Properties.Add(new PSNoteProperty("Path", row["path"]));
                result.Properties.Add(new PSNoteProperty("RemotePath", remotefile));
                result.Properties.Add(new PSNoteProperty("MaxSize", row["max_size"]));
                result.Properties.Add(new PSNoteProperty("StopTime", row["stop_time"]));
                result.Properties.Add(new PSNoteProperty("MaxFiles", row["max_files"]));
                result.Properties.Add(new PSNoteProperty("IsRowset", row["is_rowset"]));
                result.Properties.Add(new PSNoteProperty("IsRollover", row["is_rollover"]));
                result.Properties.Add(new PSNoteProperty("IsShutdown", row["is_shutdown"]));
                result.Properties.Add(new PSNoteProperty("IsDefault", row["is_default"]));
                result.Properties.Add(new PSNoteProperty("BufferCount", row["buffer_count"]));
                result.Properties.Add(new PSNoteProperty("BufferSize", row["buffer_size"]));
                result.Properties.Add(new PSNoteProperty("FilePosition", row["file_position"]));
                result.Properties.Add(new PSNoteProperty("ReaderSpid", row["reader_spid"]));
                result.Properties.Add(new PSNoteProperty("StartTime", row["start_time"]));
                result.Properties.Add(new PSNoteProperty("LastEventTime", row["last_event_time"]));
                result.Properties.Add(new PSNoteProperty("EventCount", row["event_count"]));
                result.Properties.Add(new PSNoteProperty("DroppedEventCount", row["dropped_event_count"]));
                result.Properties.Add(new PSNoteProperty("Parent", server));

                // PS: Select-DefaultView -ExcludeProperty Parent, RemotePath, RemoStatus, SqlCredential
                // (RemoStatus is a typo in the PS source; excluding a nonexistent name is a no-op)
                OutputHelper.SetDefaultDisplayPropertySetExcluding(result, new[] { "Parent", "RemotePath", "RemoStatus", "SqlCredential" });

                WriteObject(result);
            }
        }
    }

    private static bool ToBool(object value)
    {
        if (value is DBNull || value is null)
        {
            return false;
        }
        try { return Convert.ToBoolean(value); }
        catch { return false; }
    }

    private static string JoinAdminUnc(string? servername, string filepath)
    {
        // Inline of private/functions/Join-AdminUnc.ps1: \\server\c$\path admin share form.
        // The PS original returns the path unchanged on Linux/macOS ($IsLinux/$IsMacOs guard).
        if (string.IsNullOrEmpty(filepath) || filepath.StartsWith("\\\\", StringComparison.Ordinal) || Environment.OSVersion.Platform != PlatformID.Win32NT)
        {
            return filepath;
        }
        string host = (servername ?? "").Split('\\')[0];
        // The PS source is Join-Path "\\server\" (filepath with : -> $), and Join-Path does two
        // things a raw concat does not: it normalizes forward slashes to backslashes and it
        // collapses the single duplicate separator at the parent/child boundary. Replicate both so
        // a root-relative ("\logs\x") or forward-slash ("/logs/x") path yields "\\server\logs\x"
        // rather than a malformed "\\server\\logs\x" / "\\server\/logs/x".
        string child = filepath.Replace(':', '$').Replace('/', '\\');
        if (child.Length > 0 && child[0] == '\\')
        {
            child = child.Substring(1);
        }
        return "\\\\" + host + "\\" + child;
    }
}
