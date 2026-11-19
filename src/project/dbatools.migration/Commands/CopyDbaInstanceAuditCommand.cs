#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies server audits between instances. Port of public/Copy-DbaInstanceAudit.ps1. The workflow
/// rides one module-scoped PowerShell hop: it leans on the private Get-ErrorMessage,
/// Get-SqlDefaultPaths, Join-AdminUnc and Select-DefaultView, and on SMO Audit.Script() plus
/// Server.Query, so the engine semantics stay where they were. The compiled cmdlet supplies the real
/// ShouldProcess runtime. Surface pinned by migration/baselines/Copy-DbaInstanceAudit.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaInstanceAudit", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaInstanceAuditCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the server audits with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? Audit { get; set; }

    /// <summary>Skip the server audits with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeAudit { get; set; }

    /// <summary>Directory the destination audit files are written to.</summary>
    [Parameter(Position = 6)]
    public string? Path { get; set; }

    /// <summary>Drop and recreate audits that already exist, and create missing audit directories.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin and process stay in one hop, and there are no carried locals: no parameter takes
    // pipeline input, so ProcessRecord runs exactly once and nothing can survive between records.
    // Test-FunctionInterrupt still earns its line inside the script - the begin half's source
    // connect failure has to stop the destination loop that follows in the same invocation.
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
            Audit, ExcludeAudit, Path, Force.ToBool(),
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Audit, $ExcludeAudit, $Path, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # $Force is deliberately untyped: PowerShell excludes [switch] parameters from positional
    # binding, so one typed flag would shift every argument after it. It arrives as a real boolean,
    # which the -eq $false tests below read the way a switch reads.
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [object[]]$Audit, [object[]]$ExcludeAudit, [string]$Path, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaInstanceAudit
        return
    }
    $serverAudits = $sourceServer.Audits

    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }

    foreach ($destinstance in $Destination) {

        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaInstanceAudit
        }
        $destAudits = $destServer.Audits
        foreach ($currentAudit in $serverAudits) {
            $auditName = $currentAudit.Name

            $copyAuditStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $auditName
                Type              = "Server Audit"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($Audit -and $auditName -notin $Audit -or $auditName -in $ExcludeAudit) {
                continue
            }

            if ($Path) {
                $currentAudit.FilePath = $Path
            }

            if ($destAudits.Name -contains $auditName) {
                if ($force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Server audit $auditName exists at destination. Use -Force to drop and migrate.")) {
                        $copyAuditStatus.Status = "Skipped"
                        $copyAuditStatus.Notes = "Already exists on destination"
                        Write-Message -Level Verbose -Message "Server audit $auditName exists at destination. Use -Force to drop and migrate." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                    }
                    continue
                } else {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Dropping server audit $auditName")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping server audit $auditName." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                            foreach ($spec in $destServer.ServerAuditSpecifications) {
                                if ($auditSpecification.Auditname -eq $auditName) {
                                    $auditSpecification.Drop()
                                }
                            }

                            $destServer.audits[$auditName].Disable()
                            $destServer.audits[$auditName].Alter()
                            $destServer.audits[$auditName].Drop()
                        } catch {
                            $copyAuditStatus.Status = "Failed"
                            $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping audit from $destinstance | $PSItem" -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                            continue
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($currentAudit.Filepath) -and -not (Test-DbaPath -SqlInstance $destServer -Path $currentAudit.Filepath)) {
                if ($Force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory.")) {
                        $copyAuditStatus.Status = "Skipped"
                        $copyAuditStatus.Notes = "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory."
                        $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                } else {
                    Write-Message -Level Verbose -Message "Force specified. Creating directory." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"

                    $resolvedComputerName = Resolve-DbaComputerName -ComputerName $destServer
                    $root = $currentAudit.Filepath.Substring(0, 3)
                    $rootUnc = Join-AdminUnc $resolvedComputerName $root

                    if ((Test-Path $rootUnc) -eq $true) {
                        if ($__realCmdlet.ShouldProcess($destinstance, "Creating directory $($currentAudit.Filepath)")) {
                            try {
                                $null = New-DbaDirectory -SqlInstance $destServer -Path $currentAudit.Filepath -EnableException
                            } catch {
                                Write-Message -Level Warning -Message "Couldn't create directory $($currentAudit.Filepath). Using default data directory." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                                $datadir = Get-SqlDefaultPaths $destServer data
                                $currentAudit.FilePath = $datadir
                            }
                        }
                    } else {
                        $datadir = Get-SqlDefaultPaths $destServer data
                        $currentAudit.FilePath = $datadir
                    }
                }
            }
            if ($__realCmdlet.ShouldProcess($destinstance, "Creating server audit $auditName")) {
                try {
                    Write-Message -Level Verbose -Message "File path $($currentAudit.Filepath) exists on $destinstance." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Copying server audit $auditName." -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                    $sql = $currentAudit.Script() | Out-String
                    $destServer.Query($sql)
                    $copyAuditStatus.Status = "Successful"
                    $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyAuditStatus.Status = "Failed"
                    $copyAuditStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue creating audit on $destinstance | $PSItem" -FunctionName Copy-DbaInstanceAudit -ModuleName "dbatools"
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Audit $ExcludeAudit $Path $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
