#nullable enable

using System;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Extracts backup metadata from SQL Server backup files without restoring them, via
/// RESTORE HEADERONLY on a live instance, with multithreaded scanning of multiple files.
/// Port of public/Read-DbaBackupHeader.ps1; surface pinned by
/// migration/baselines/Read-DbaBackupHeader.json.
/// </summary>
[Cmdlet(VerbsCommunications.Read, "DbaBackupHeader")]
[OutputType(typeof(DataRow))]
public sealed partial class ReadDbaBackupHeaderCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>File paths to SQL Server backup files; must be accessible from the target instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 2)]
    public object[] Path { get; set; } = null!;

    /// <summary>Returns a simplified output with only essential columns.</summary>
    [Parameter]
    public SwitchParameter Simple { get; set; }

    /// <summary>Returns detailed information about each data and log file contained within the backup set.</summary>
    [Parameter]
    public SwitchParameter FileList { get; set; }

    /// <summary>Name of a SQL Server credential object for Azure blob storage or S3-compatible object storage access.</summary>
    [Parameter(Position = 3)]
    [Alias("AzureCredential", "S3Credential")]
    public string? StorageCredential { get; set; }

    private Server? _server;

    protected override void BeginProcessing()
    {
        // begin{} only ever sees the parameter-bound Path; pipeline input arrives in process.
        if (Path is not null)
        {
            foreach (object p in Path)
            {
                WriteMessage(MessageLevel.Verbose, $"Checking: {RestoreUtility.PsStringify(p)}");
                if (System.IO.Path.GetExtension(RestoreUtility.PsStringify(p)).Length == 0)
                {
                    // PS: Stop-Function -Message "Path ("$p") should be a file, not a folder" — string concatenation.
                    StopFunction($"Path ({RestoreUtility.PsStringify(p)}) should be a file, not a folder", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
        }
        WriteMessage(MessageLevel.InternalComment, "Starting reading headers");
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = SqlInstance,
                SqlCredential = SqlCredential
            };
            _server = ConnectionService.GetServer(request);
            SetActiveConnection(_server.ConnectionContext);
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Read-DbaBackupHeader", ErrorCategory.ConnectionError, SqlInstance);
            StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return;
        }
    }
}
