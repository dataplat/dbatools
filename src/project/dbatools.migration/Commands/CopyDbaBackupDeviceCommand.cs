#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies SQL Server backup devices between instances, moving both the device definition and the
/// physical backup file. Port of public/Copy-DbaBackupDevice.ps1. The complete workflow remains a
/// module-scoped PowerShell compatibility hop because the body leans on admin-share UNC helpers,
/// Test-DbaPath, SMO scripting and BITS transfer, all of which retain engine semantics there.
/// The compiled cmdlet supplies the real ShouldProcess runtime.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaBackupDevice", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaBackupDeviceCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy backup devices with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? BackupDevice { get; set; }

    /// <summary>Drop and recreate backup devices that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential,
            BackupDevice, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $BackupDevice, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [object[]]$BackupDevice, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    if (-not $script:isWindows) {
        Stop-Function -Message "Copy-DbaBackupDevice does not support Linux yet though it looks doable" -FunctionName Copy-DbaBackupDevice
        return
    }
    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaBackupDevice
        return
    }
    $serverBackupDevices = $sourceServer.BackupDevices
    $sourceNetBios = $Source.ComputerName

    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaBackupDevice
        }
        $destBackupDevices = $destServer.BackupDevices
        $destNetBios = $destinstance.ComputerName

        foreach ($currentBackupDevice in $serverBackupDevices) {
            $deviceName = $currentBackupDevice.Name

            $copyBackupDeviceStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $deviceName
                Type              = "Backup Device"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($BackupDevice -and $BackupDevice -notcontains $deviceName) {
                continue
            }

            if ($destBackupDevices.Name -contains $deviceName) {
                if ($force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Backup device $deviceName exists at destination. Use -Force to drop and migrate.")) {
                        $copyBackupDeviceStatus.Status = "Skipped"
                        $copyBackupDeviceStatus.Notes = "Already exists on destination"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Backup device $deviceName exists at destination. Use -Force to drop and migrate." -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                    }
                    continue
                } else {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Dropping backup device $deviceName")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping backup device $deviceName" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                            $destServer.BackupDevices[$deviceName].Drop()
                        } catch {
                            $copyBackupDeviceStatus.Status = "Failed"
                            $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping backup device $deviceName on $destinstance | $PSItem" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                            continue
                        }
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Generating SQL code for $deviceName")) {
                Write-Message -Level Verbose -Message "Scripting out SQL for $deviceName" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                try {
                    $sql = $currentBackupDevice.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                } catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue scripting out backup device $deviceName on $destinstance | $PSItem" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Preparing to copy actual backup file" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"

            $path = Split-Path $sourceServer.BackupDevices[$deviceName].PhysicalLocation
            $destPath = Join-AdminUnc $destNetBios $path
            $sourcepath = Join-AdminUnc $sourceNetBios $sourceServer.BackupDevices[$deviceName].PhysicalLocation

            Write-Message -Level Verbose -Message "Checking if directory $destPath exists" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"

            if ($(Test-DbaPath -SqlInstance $destServer -Path $path) -eq $false) {
                $backupDirectory = $destServer.BackupDirectory
                $destPath = Join-AdminUnc $destNetBios $backupDirectory

                if ($__realCmdlet.ShouldProcess($destinstance, "Updating create code to use new path")) {
                    Write-Message -Level Verbose -Message "$path doesn't exist on $destinstance" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Using default backup directory $backupDirectory" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"

                    try {
                        Write-Message -Level Verbose -Message "Updating $deviceName to use $backupDirectory" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                        $sql = $sql -replace [Regex]::Escape($path), $backupDirectory
                    } catch {
                        $copyBackupDeviceStatus.Status = "Failed"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue updating script of backup device $deviceName with new path on $destinstance | $PSItem" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                        continue
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Copying $sourcepath to $destPath using BITSTransfer")) {
                try {
                    Start-BitsTransfer -Source $sourcepath -Destination $destPath -ErrorAction Stop
                    Write-Message -Level Verbose -Message "Backup device $deviceName successfully copied" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                } catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue copying $sourcepath to $destPath for backup device $deviceName on $destinstance | $PSItem" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                    continue
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Adding backup device $deviceName")) {
                Write-Message -Level Verbose -Message "Adding backup device $deviceName on $destinstance" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                try {
                    $destServer.Query($sql)
                    $destServer.BackupDevices.Refresh()

                    $copyBackupDeviceStatus.Status = "Successful"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue creating backup device $deviceName on $destinstance | $PSItem" -FunctionName Copy-DbaBackupDevice -ModuleName "dbatools"
                    continue
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $BackupDevice $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
