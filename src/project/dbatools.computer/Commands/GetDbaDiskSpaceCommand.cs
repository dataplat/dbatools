#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Computer;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Displays disk and volume space information from SQL Server host computers.
/// Port of public/Get-DbaDiskSpace.ps1; surface pinned by migration/baselines/Get-DbaDiskSpace.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDiskSpace")]
[OutputType(typeof(DiskSpace))]
public sealed class GetDbaDiskSpaceCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate Windows credential for the CIM connection.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Display unit (legacy; the DiskSpace object exposes all unit conversions).</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("Bytes", "KB", "MB", "GB", "TB", "PB")]
    public string Unit { get; set; } = "GB";

    /// <summary>Legacy parameter kept for surface compatibility; not consumed.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filter out drives (as named in the Name property, e.g. "C:\").</summary>
    [Parameter(Position = 4)]
    public string[]? ExcludeDrive { get; set; }

    /// <summary>Legacy parameter kept for surface compatibility; not consumed.</summary>
    [Parameter]
    public SwitchParameter CheckFragmentation { get; set; }

    /// <summary>Includes all drive types and UNC-named volumes in the scan.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // PS begin block: the WHERE clause is computed once, and processed computers are
    // tracked across the whole pipeline to avoid duplicates.
    private string _condition = " WHERE DriveType = 2 OR DriveType = 3";
    private readonly List<string> _processed = new();

    protected override void BeginProcessing()
    {
        // PS: if (Test-Bound 'Force') { $condition = "" } - bound presence, not value.
        if (TestBound(nameof(Force)))
        {
            _condition = string.Empty;
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            // PS: -notin over the processed list is case-insensitive
            bool seen = false;
            foreach (string done in _processed)
            {
                if (string.Equals(done, computer.ComputerName, StringComparison.OrdinalIgnoreCase))
                {
                    seen = true;
                    break;
                }
            }
            if (seen)
            {
                continue;
            }
            _processed.Add(computer.ComputerName);

            CimService.CmObjectResult disks;
            try
            {
                CimService.CmObjectRequest request = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    Query = $"SELECT * FROM Win32_Volume{_condition}",
                    Namespace = @"root\CIMv2"
                };
                disks = CimService.GetCmObject(this, request);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to connect to {computer}.", target: computer.ComputerName, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaDiskSpace", ErrorCategory.NotSpecified, computer.ComputerName), continueLoop: true);
                continue;
            }
            foreach (ErrorRecord error in disks.PassthroughErrors)
            {
                WriteError(NestedCommand.PreserveErrorIdentity(error));
            }

            foreach (PSObject disk in disks.Instances)
            {
                string? diskName = GetValue(disk, "Name")?.ToString();
                if (diskName is null)
                {
                    diskName = string.Empty;
                }
                if (ContainsIgnoreCase(ExcludeDrive, diskName))
                {
                    continue;
                }
                if (diskName.StartsWith(@"\\", StringComparison.Ordinal) && !Force.ToBool())
                {
                    WriteMessage(MessageLevel.Verbose, $"Skipping disk: {diskName}", target: computer.ComputerName);
                    continue;
                }

                WriteMessage(MessageLevel.Verbose, $"Processing disk: {diskName}", target: computer.ComputerName);

                DiskSpace info = new();
                info.ComputerName = computer.ComputerName;
                info.Name = diskName;
                info.Label = GetValue(disk, "Label") as string;
                info.Capacity = ToSize(GetValue(disk, "Capacity"));
                info.Free = ToSize(GetValue(disk, "Freespace"));
                info.BlockSize = ToInt(GetValue(disk, "BlockSize"));
                info.FileSystem = GetValue(disk, "FileSystem") as string;
                info.Type = (DriveType)ToInt(GetValue(disk, "DriveType"));
                WriteObject(info);
            }
        }
    }

    private static object? GetValue(PSObject instance, string name)
    {
        return instance.Properties[name]?.Value;
    }

    private static bool ContainsIgnoreCase(string[]? values, string candidate)
    {
        if (values is null)
        {
            return false;
        }
        foreach (string value in values)
        {
            if (string.Equals(value, candidate, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static Size? ToSize(object? value)
    {
        if (value is null)
        {
            return null;
        }
        return new Size(Convert.ToInt64(value, CultureInfo.InvariantCulture));
    }

    private static int ToInt(object? value)
    {
        if (value is null)
        {
            return 0;
        }
        return Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
