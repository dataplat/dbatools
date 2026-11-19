#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies data out of a view into a table. Port of public/Copy-DbaDbViewData.ps1, whose whole
/// process block is one line - it forwards its bound parameters to Copy-DbaDbTableData and does
/// nothing else. The forward rides a module-scoped hop so the name resolves the way it does for
/// every other in-module caller. Surface pinned by migration/baselines/Copy-DbaDbViewData.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDbViewData", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDbViewDataCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter[]? Destination { get; set; }

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Source database holding the view to copy from.</summary>
    [Parameter(Position = 4)]
    public string? Database { get; set; }

    /// <summary>Target database the copied data is written to.</summary>
    [Parameter(Position = 5)]
    public string? DestinationDatabase { get; set; }

    /// <summary>Source view names, 2-part or 3-part.</summary>
    [Parameter(Position = 6)]
    public string[]? View { get; set; }

    /// <summary>Custom SELECT used as the data source instead of the whole view.</summary>
    [Parameter(Position = 7)]
    public string? Query { get; set; }

    /// <summary>Create the destination table from the source structure when it is missing.</summary>
    [Parameter]
    public SwitchParameter AutoCreateTable { get; set; }

    /// <summary>Rows per bulk copy batch.</summary>
    [Parameter(Position = 8)]
    public int BatchSize { get; set; } = 50000;

    /// <summary>Rows between progress notifications.</summary>
    [Parameter(Position = 9)]
    public int NotifyAfter { get; set; } = 5000;

    /// <summary>Target table name.</summary>
    [Parameter(Position = 10)]
    public string? DestinationTable { get; set; }

    /// <summary>Drop the default TABLOCK on the destination table.</summary>
    [Parameter]
    public SwitchParameter NoTableLock { get; set; }

    /// <summary>Check constraints during the bulk copy.</summary>
    [Parameter]
    public SwitchParameter CheckConstraints { get; set; }

    /// <summary>Fire INSERT triggers during the bulk copy.</summary>
    [Parameter]
    public SwitchParameter FireTriggers { get; set; }

    /// <summary>Preserve source identity values.</summary>
    [Parameter]
    public SwitchParameter KeepIdentity { get; set; }

    /// <summary>Preserve source NULLs instead of destination defaults.</summary>
    [Parameter]
    public SwitchParameter KeepNulls { get; set; }

    /// <summary>Truncate the destination table before copying.</summary>
    [Parameter]
    public SwitchParameter Truncate { get; set; }

    // Spelled with the capital O the retired function used. Copy-DbaDbTableData spells the same
    // parameter BulkCopyTimeout, and the splat below still binds it because parameter binding is
    // case-insensitive - renaming it here would break every caller instead.
    /// <summary>Seconds the bulk copy may run before timing out.</summary>
    [Parameter(Position = 11)]
    public int BulkCopyTimeOut { get; set; } = 5000;

    /// <summary>Scripting options governing an auto-created destination table.</summary>
    [Parameter(Position = 12)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>View or table objects from Get-DbaDbView or Get-DbaDbTable.</summary>
    [Parameter(Position = 13, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.TableViewBase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // No cross-record carriers: the source's process block declares no locals at all, so there is
    // nothing that could survive between piped records. No Interrupted guard either - the source
    // has no Stop-Function and no Test-FunctionInterrupt.
    protected override void ProcessRecord()
    {
        // The source splats its own $PSBoundParameters, so the hop needs the caller's real bound
        // set rather than the hop's. Rebuilt per record because InputObject is the pipeline
        // parameter: its value is what changes between records, and a bag captured once would
        // forward record 1's view for every record after it.
        Hashtable realBound = new Hashtable(MyInvocation.BoundParameters);
        if (realBound.ContainsKey(nameof(InputObject)))
        {
            realBound[nameof(InputObject)] = InputObject;
        }

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
        }, BodyScript, realBound);
    }

    // PS: the process block verbatim. $PSBoundParameters is reseeded from the carried set as the
    // block's first statement because the hop's own bag reflects the hop's binding, not the
    // caller's - the forward would otherwise splat the wrong parameters.
    private const string BodyScript = """
param($__realBoundParameters)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($__realBoundParameters)

    $PSBoundParameters = $__realBoundParameters
    Copy-DbaDbTableData @PSBoundParameters
} $__realBoundParameters 3>&1 2>&1
""";
}
