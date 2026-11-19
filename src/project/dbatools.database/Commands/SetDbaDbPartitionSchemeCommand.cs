#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoPartitionScheme = Microsoft.SqlServer.Management.Smo.PartitionScheme;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets (or resets) the NEXT USED filegroup on an existing partition scheme and re-emits the refreshed scheme
/// decorated like Get-DbaDbPartitionScheme.
/// </summary>
/// <remarks>
/// NextUsedFileGroup is the only alterable property of a partition scheme, and it is the filegroup a subsequent
/// SPLIT RANGE will use - so this is the command Set-DbaDbPartitionFunction -SplitRangePartition depends on. The
/// change goes through Alter(): SMO's ScriptAlter emits 'ALTER PARTITION SCHEME &lt;name&gt; NEXT USED [fg]' only
/// when the value is non-null and dirty, so a no-op assignment scripts nothing.
///
/// -ResetNextUsedFileGroup clears the setting by assigning an empty string and calling Alter() (which emits the
/// bare 'NEXT USED' reset form). It deliberately does NOT use SMO's ResetNextUsed(), which builds a broken
/// 'ALTER PARTITION FUNCTION ... NEXT USED' statement against the scheme's name and cannot succeed on any server.
/// -NextUsedFileGroup and -ResetNextUsedFileGroup are mutually exclusive; a switch is used for reset so an
/// accidental empty string is not read as a reset. Either -SqlInstance or a piped Get-DbaDbPartitionScheme
/// object (the Test-Bound duality, no parameter sets).
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbPartitionScheme", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoPartitionScheme))]
public sealed class SetDbaDbPartitionSchemeCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to look in when resolving schemes by name.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name(s) of the partition scheme(s) to modify (on the -SqlInstance path).</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? PartitionScheme { get; set; }

    /// <summary>The filegroup the next SPLIT RANGE will use. Mutually exclusive with -ResetNextUsedFileGroup.</summary>
    [Parameter(Position = 4)]
    public string? NextUsedFileGroup { get; set; }

    /// <summary>Clears the NEXT USED filegroup. Mutually exclusive with -NextUsedFileGroup.</summary>
    [Parameter]
    public SwitchParameter ResetNextUsedFileGroup { get; set; }

    /// <summary>Partition scheme object(s) piped in from Get-DbaDbPartitionScheme.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public SmoPartitionScheme[]? InputObject { get; set; }

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
            SqlInstance, SqlCredential, Database, PartitionScheme, NextUsedFileGroup,
            ResetNextUsedFileGroup.ToBool(), InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(PartitionScheme)),
            TestBound(nameof(NextUsedFileGroup)), TestBound(nameof(ResetNextUsedFileGroup)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Schemes come from -SqlInstance (resolved via Get-DbaDbPartitionScheme) or piped
    // -InputObject. Exactly one of -NextUsedFileGroup / -ResetNextUsedFileGroup is required. The assignment (or
    // empty-string reset) plus Alter() runs inside a passed ShouldProcess so -WhatIf never touches the server.
    // The refreshed scheme is re-emitted via Get-DbaDbPartitionScheme.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $PartitionScheme, $NextUsedFileGroup, $ResetNextUsedFileGroup, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundPartitionScheme, $__boundNextUsed, $__boundReset, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$PartitionScheme, [string]$NextUsedFileGroup, $ResetNextUsedFileGroup, [Microsoft.SqlServer.Management.Smo.PartitionScheme[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundPartitionScheme, $__boundNextUsed, $__boundReset)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbPartitionScheme
        return
    }

    if ($__boundNextUsed -and $__boundReset) {
        Stop-Function -Message "-NextUsedFileGroup and -ResetNextUsedFileGroup are mutually exclusive; specify only one." -FunctionName Set-DbaDbPartitionScheme
        return
    }

    if (-not $__boundNextUsed -and -not $__boundReset) {
        Stop-Function -Message "You must specify either -NextUsedFileGroup or -ResetNextUsedFileGroup." -FunctionName Set-DbaDbPartitionScheme
        return
    }

    $schemesToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $schemesToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbPartitionScheme -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -PartitionScheme $PartitionScheme -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbPartitionScheme
                continue
            }
            foreach ($f in $found) { $schemesToProcess.Add($f) }
        }
    }

    foreach ($ps in $schemesToProcess) {
        $db = $ps.Parent
        $server = $db.Parent

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Setting next used filegroup on partition scheme $($ps.Name) in database $($db.Name)")) {
            try {
                if ($__boundReset) {
                    # Empty string routes through the correct ScriptAlter reset form; SMO's ResetNextUsed() is broken.
                    $ps.NextUsedFileGroup = ""
                } else {
                    $ps.NextUsedFileGroup = $NextUsedFileGroup
                }
                $ps.Alter()
                $ps.Refresh()
            } catch {
                Stop-Function -Message "Failed to set next used filegroup on partition scheme $($ps.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $ps -Continue -FunctionName Set-DbaDbPartitionScheme
                continue
            }

            Get-DbaDbPartitionScheme -SqlInstance $server -Database $db.Name -PartitionScheme $ps.Name
        }
    }
} $SqlInstance $SqlCredential $Database $PartitionScheme $NextUsedFileGroup $ResetNextUsedFileGroup $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundPartitionScheme $__boundNextUsed $__boundReset @__commonParameters 3>&1 2>&1
""";
}
