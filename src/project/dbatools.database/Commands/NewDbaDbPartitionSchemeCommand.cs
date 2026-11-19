#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoPartitionScheme = Microsoft.SqlServer.Management.Smo.PartitionScheme;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a partition scheme in one or more databases and re-emits the created scheme decorated like
/// Get-DbaDbPartitionScheme.
/// </summary>
/// <remarks>
/// Get-DbaDbPartitionScheme and Remove-DbaDbPartitionScheme existed but there was no way to create one; this
/// closes that gap. The database resolution, existence check, scheme creation and output all run a module-scoped
/// PowerShell body inside the dbatools module scope. Brand-new command with no PowerShell ancestor; the surface
/// is pinned by the owner-signed designed spec and diffed EXACT-match in the gate.
///
/// SINGLE-FILEGROUP EXPANSION IS THIS COMMAND'S JOB, NOT SMO'S: the T-SQL 'ALL TO ([fg])' shorthand is not
/// reachable through SMO (ScriptCreate always enumerates the FileGroups collection), so when the caller passes a
/// single -FileGroup this command repeats it N times, where N is the target function's NumberOfPartitions
/// (boundaries + 1). An empty FileGroups collection makes SMO throw, so -FileGroup is validated non-empty.
/// -PartitionFunction is a NAME string (the property is a by-name binding, not a typed object reference), and it
/// must already exist. No -Schema (the constructor has no schema-qualified overload); NextUsedFileGroup belongs
/// to Set-DbaDbPartitionScheme, not create time.
///
/// SAFETY: the sole Create runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. An existing scheme is refused with a pointer at Set-DbaDbPartitionScheme. Either
/// -SqlInstance or a piped database (the Test-Bound duality, no parameter sets).
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbPartitionScheme", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoPartitionScheme))]
public sealed class NewDbaDbPartitionSchemeCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the partition scheme is created in.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name of the partition scheme to create.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>The name of the existing partition function the scheme binds to.</summary>
    [Parameter(Position = 4)]
    public string? PartitionFunction { get; set; }

    /// <summary>The filegroup(s) to map partitions to. A single value is expanded across all partitions.</summary>
    [Parameter(Position = 5)]
    [Alias("FileGroups")]
    public string[]? FileGroup { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the designed spec declares it in __AllParameterSets.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Database, Name, PartitionFunction, FileGroup,
            InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Databases come from -SqlInstance (resolved via Get-DbaDatabase) or piped
    // -InputObject. -PartitionFunction must name an existing function; a single -FileGroup is expanded to the
    // function's NumberOfPartitions. An existing scheme is refused (pointing at Set-DbaDbPartitionScheme);
    // creation sets PartitionFunction, adds the filegroups and runs inside a passed ShouldProcess so -WhatIf
    // never touches the server. The created scheme is re-emitted via Get-DbaDbPartitionScheme.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $PartitionFunction, $FileGroup, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Name, [string]$PartitionFunction, [string[]]$FileGroup, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName New-DbaDbPartitionScheme
        return
    }

    if (-not $Name) {
        Stop-Function -Message "You must specify the partition scheme name with -Name" -FunctionName New-DbaDbPartitionScheme
        return
    }

    if (-not $PartitionFunction) {
        Stop-Function -Message "You must specify the partition function name with -PartitionFunction" -FunctionName New-DbaDbPartitionScheme
        return
    }

    if (-not $FileGroup -or $FileGroup.Count -eq 0) {
        Stop-Function -Message "You must specify at least one filegroup with -FileGroup" -FunctionName New-DbaDbPartitionScheme
        return
    }

    if ($__boundSqlInstance) {
        try {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaDbPartitionScheme
            return
        }
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.IsAccessible) {
            Stop-Function -Message "Database $($db.Name) is not accessible. Skipping." -Target $db -Continue -FunctionName New-DbaDbPartitionScheme
            continue
        }

        $existing = $db.PartitionSchemes | Where-Object { $_.Name -eq $Name }
        if ($existing) {
            Stop-Function -Message "Partition scheme $Name already exists in database $($db.Name) on $($server.DomainInstanceName). Use Set-DbaDbPartitionScheme to modify it." -Target $db -Continue -FunctionName New-DbaDbPartitionScheme
            continue
        }

        $targetFunction = $db.PartitionFunctions | Where-Object { $_.Name -eq $PartitionFunction }
        if (-not $targetFunction) {
            Stop-Function -Message "Partition function $PartitionFunction does not exist in database $($db.Name) on $($server.DomainInstanceName). Create it with New-DbaDbPartitionFunction first." -Target $db -Continue -FunctionName New-DbaDbPartitionScheme
            continue
        }

        # A single filegroup maps every partition; SMO has no ALL TO shorthand, so expand to NumberOfPartitions.
        $fileGroupList = $FileGroup
        if ($FileGroup.Count -eq 1) {
            $partitionCount = $targetFunction.NumberOfPartitions
            $fileGroupList = @($FileGroup[0]) * $partitionCount
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Creating partition scheme $Name in database $($db.Name)")) {
            try {
                $ps = New-Object Microsoft.SqlServer.Management.Smo.PartitionScheme -ArgumentList $db, $Name
                $ps.PartitionFunction = $PartitionFunction
                # FileGroups.Add returns the insertion index; discard it so it does not leak to the pipeline.
                foreach ($fg in $fileGroupList) { $null = $ps.FileGroups.Add($fg) }
                $ps.Create()
                $ps.Refresh()
            } catch {
                Stop-Function -Message "Failed to create partition scheme $Name in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $db -Continue -FunctionName New-DbaDbPartitionScheme
                continue
            }

            Get-DbaDbPartitionScheme -SqlInstance $server -Database $db.Name -PartitionScheme $Name
        }
    }
} $SqlInstance $SqlCredential $Database $Name $PartitionFunction $FileGroup $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject @__commonParameters 3>&1 2>&1
""";
}
