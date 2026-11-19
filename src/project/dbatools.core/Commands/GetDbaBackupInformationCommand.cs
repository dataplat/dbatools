#nullable enable

using System;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Scans backup files and reads their headers to create structured backup history objects
/// for restore operations. Port of public/Get-DbaBackupInformation.ps1; surface pinned by
/// migration/baselines/Get-DbaBackupInformation.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaBackupInformation", DefaultParameterSetName = "Create")]
[OutputType(typeof(Dataplat.Dbatools.Database.BackupHistory))]
public sealed partial class GetDbaBackupInformationCommand : DbaBaseCmdlet
{
    /// <summary>Path to SQL Server backup files: strings to scan, or FileInfo objects from Get-ChildItem.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public object[] Path { get; set; } = null!;

    /// <summary>The SQL Server instance to be used to read the headers of the backup files.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Create")]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "Create")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>An array of Database Names to filter by. If empty all databases are returned.</summary>
    [Parameter]
    public string[]? DatabaseName { get; set; }

    /// <summary>If provided only backup originating from this destination will be returned.</summary>
    [Parameter]
    public string[]? SourceInstance { get; set; }

    /// <summary>Parse the files as local files to the SQL Server instance instead of using xp_dirtree.</summary>
    [Parameter(ParameterSetName = "Create")]
    public SwitchParameter NoXpDirTree { get; set; }

    /// <summary>Changes xp_dirtree behavior to not recurse the folder structure.</summary>
    [Parameter(ParameterSetName = "Create")]
    public SwitchParameter NoXpDirRecurse { get; set; }

    /// <summary>Traverse the provided path/directory (only applies when not using XpDirTree).</summary>
    [Parameter(ParameterSetName = "Create")]
    public SwitchParameter DirectoryRecurse { get; set; }

    /// <summary>The folder is the root of a Ola Hallengren backup folder.</summary>
    [Parameter]
    public SwitchParameter MaintenanceSolution { get; set; }

    /// <summary>With MaintenanceSolution: skip the LOG folder.</summary>
    [Parameter]
    public SwitchParameter IgnoreLogBackup { get; set; }

    /// <summary>With MaintenanceSolution: skip the DIFF folder.</summary>
    [Parameter]
    public SwitchParameter IgnoreDiffBackup { get; set; }

    /// <summary>Export the output via CliXml format to the specified file.</summary>
    [Parameter]
    public string? ExportPath { get; set; }

    /// <summary>The name of the SQL Server credential to be used if restoring from cloud storage.</summary>
    [Parameter]
    [Alias("AzureCredential", "S3Credential")]
    public string? StorageCredential { get; set; }

    /// <summary>Import a previously exported BackupHistory object from an xml file.</summary>
    [Parameter(ParameterSetName = "Import")]
    public SwitchParameter Import { get; set; }

    /// <summary>Output the results with identifying values hashed for fault-finding submissions.</summary>
    [Parameter]
    [Alias("Anonymize")]
    public SwitchParameter Anonymise { get; set; }

    /// <summary>Stop Export from overwriting an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Also return the normal output when exporting.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    private Server? _server;
    private bool _noXpDirTreeEffective;

    private static string GetHashString(string inString)
    {
        StringBuilder stringBuilder = new();
        using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
        {
            foreach (byte b in md5.ComputeHash(Encoding.UTF8.GetBytes(inString ?? string.Empty)))
                stringBuilder.Append(b.ToString("x2", System.Globalization.CultureInfo.InvariantCulture));
        }
        return stringBuilder.ToString();
    }

    protected override void BeginProcessing()
    {
        WriteMessage(MessageLevel.InternalComment, "Starting");
        WriteMessage(MessageLevel.Debug, $"Parameters bound: {string.Join(", ", MyInvocation.BoundParameters.Keys)}");

        if (TestBound("ExportPath"))
        {
            if (NoClobber.ToBool())
            {
                if (System.IO.File.Exists(ExportPath) || System.IO.Directory.Exists(ExportPath))
                {
                    StopFunction($"{ExportPath} exists and NoClobber set");
                    return;
                }
            }
        }
        if (ParameterSetName == "Create")
        {
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
                ErrorRecord record = new(ex, "dbatools_Get-DbaBackupInformation", ErrorCategory.ConnectionError, SqlInstance);
                StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
                return;
            }
        }

        _noXpDirTreeEffective = NoXpDirTree.ToBool();

        if (IgnoreLogBackup.ToBool() && !MaintenanceSolution.ToBool())
        {
            WriteMessage(MessageLevel.Warning, "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used");
        }
    }
}
