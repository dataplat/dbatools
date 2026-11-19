#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoPartitionFunction = Microsoft.SqlServer.Management.Smo.PartitionFunction;
using SmoDataType = Microsoft.SqlServer.Management.Smo.DataType;
using SmoRangeType = Microsoft.SqlServer.Management.Smo.RangeType;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a partition function in one or more databases and re-emits the created function decorated like
/// Get-DbaDbPartitionFunction.
/// </summary>
/// <remarks>
/// Get-DbaDbPartitionFunction and Remove-DbaDbPartitionFunction existed but there was no way to create one; this
/// closes that gap. The database resolution, existence check, function creation and output all run a
/// module-scoped PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the
/// body can call Get-DbaDatabase, Get-DbaDbPartitionFunction, Stop-Function and Write-Message directly. Brand-new
/// command with no PowerShell ancestor; the surface is pinned by the owner-signed designed spec and diffed
/// EXACT-match in the gate.
///
/// TWO VALIDATION GAPS SMO LEAVES OPEN, CLOSED HERE: an empty parameter collection makes ScriptCreate throw
/// (so -InputParameterType is validated as required), and a null/empty RangeValues silently scripts
/// 'FOR VALUES ()' which the server rejects (so -RangeValues is validated non-empty). RangeType.None is a real
/// bindable member that silently scripts as RIGHT, so it is rejected explicitly. -InputParameterType is a
/// Smo.DataType (not a string) so length/precision/scale survive; -RangeValues is Object[] because boundary
/// values are genuinely typed and SMO formats them through its typed object parameter. No -Schema: the
/// PartitionFunction constructor has no schema-qualified overload and partition functions are not schema-scoped.
///
/// SAFETY: the sole Create runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. An existing function is refused with a pointer at Set-DbaDbPartitionFunction rather than
/// silently altered. Either -SqlInstance or a piped database (the Test-Bound duality, no parameter sets).
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbPartitionFunction", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoPartitionFunction))]
public sealed class NewDbaDbPartitionFunctionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the partition function is created in.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name of the partition function to create.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>The data type of the partitioning column (Smo.DataType, so precision/scale survive).</summary>
    [Parameter(Position = 4)]
    public SmoDataType? InputParameterType { get; set; }

    /// <summary>RANGE LEFT (default) or RANGE RIGHT. RangeType.None is rejected.</summary>
    [Parameter(Position = 5)]
    public SmoRangeType RangeType { get; set; }

    /// <summary>The boundary values (typed to the partitioning column). Cannot be empty.</summary>
    [Parameter(Position = 6)]
    public object[]? RangeValues { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
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
            SqlInstance, SqlCredential, Database, Name, InputParameterType, RangeType, RangeValues,
            InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(InputParameterType)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Databases come from -SqlInstance (resolved via Get-DbaDatabase) or piped
    // -InputObject. -InputParameterType (required), -RangeValues (non-empty) and -RangeType (not None) are
    // validated up front - the SMO gaps the designed spec documents. An existing function is refused (pointing at
    // Set-DbaDbPartitionFunction); creation adds a PartitionFunctionParameter(function, DataType), sets RangeType
    // and RangeValues, and runs inside a passed ShouldProcess so -WhatIf never touches the server. The created
    // function is re-emitted via Get-DbaDbPartitionFunction so its decoration matches exactly.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $InputParameterType, $RangeType, $RangeValues, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundInputParameterType, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Name, [Microsoft.SqlServer.Management.Smo.DataType]$InputParameterType, [Microsoft.SqlServer.Management.Smo.RangeType]$RangeType, [object[]]$RangeValues, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundInputParameterType)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName New-DbaDbPartitionFunction
        return
    }

    if (-not $Name) {
        Stop-Function -Message "You must specify the partition function name with -Name" -FunctionName New-DbaDbPartitionFunction
        return
    }

    if (-not $__boundInputParameterType) {
        Stop-Function -Message "You must specify the partitioning column data type with -InputParameterType" -FunctionName New-DbaDbPartitionFunction
        return
    }

    if (-not $RangeValues -or $RangeValues.Count -eq 0) {
        Stop-Function -Message "You must specify at least one boundary value with -RangeValues" -FunctionName New-DbaDbPartitionFunction
        return
    }

    if ($RangeType -eq [Microsoft.SqlServer.Management.Smo.RangeType]::None) {
        Stop-Function -Message "-RangeType must be Left or Right; None is not a valid range direction." -FunctionName New-DbaDbPartitionFunction
        return
    }

    if ($__boundSqlInstance) {
        try {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaDbPartitionFunction
            return
        }
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.IsAccessible) {
            Stop-Function -Message "Database $($db.Name) is not accessible. Skipping." -Target $db -Continue -FunctionName New-DbaDbPartitionFunction
            continue
        }

        $existing = $db.PartitionFunctions | Where-Object { $_.Name -eq $Name }
        if ($existing) {
            Stop-Function -Message "Partition function $Name already exists in database $($db.Name) on $($server.DomainInstanceName). Use Set-DbaDbPartitionFunction to modify it." -Target $db -Continue -FunctionName New-DbaDbPartitionFunction
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Creating partition function $Name in database $($db.Name)")) {
            try {
                $pf = New-Object Microsoft.SqlServer.Management.Smo.PartitionFunction -ArgumentList $db, $Name
                $pfParam = New-Object Microsoft.SqlServer.Management.Smo.PartitionFunctionParameter -ArgumentList $pf, $InputParameterType
                $pf.PartitionFunctionParameters.Add($pfParam)
                $pf.RangeType = $RangeType
                $pf.RangeValues = $RangeValues
                $pf.Create()
                $pf.Refresh()
            } catch {
                Stop-Function -Message "Failed to create partition function $Name in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $db -Continue -FunctionName New-DbaDbPartitionFunction
                continue
            }

            Get-DbaDbPartitionFunction -SqlInstance $server -Database $db.Name -PartitionFunction $Name
        }
    }
} $SqlInstance $SqlCredential $Database $Name $InputParameterType $RangeType $RangeValues $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundInputParameterType @__commonParameters 3>&1 2>&1
""";
}
