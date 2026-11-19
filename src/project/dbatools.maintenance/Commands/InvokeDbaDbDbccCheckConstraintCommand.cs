#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates constraint integrity via DBCC CHECKCONSTRAINTS. The begin-block query construction
/// (the option-driven WITH clauses keyed off which switches the caller bound), the per-instance
/// connect, the per-database enumeration with its #options# object substitution, the two
/// ShouldProcess gates, and the two-path result shaping remain a module-scoped PowerShell
/// compatibility hop; the compiled cmdlet supplies the begin/process lifetime, routes both
/// ShouldProcess gates through its real runtime (ConfirmImpact Low), carries the begin-scoped
/// query builder into the process hop, and carries the function-scoped $results the source leaks
/// across pipeline records. Surface pinned by
/// migration/baselines/Invoke-DbaDbDbccCheckConstraint.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbDbccCheckConstraint", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class InvokeDbaDbDbccCheckConstraintCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Databases to check for constraint violations. Wildcards supported.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The table or constraint (name or numeric id) to check.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Object { get; set; }

    /// <summary>Checks both enabled and disabled constraints (WITH ALL_CONSTRAINTS).</summary>
    [Parameter]
    public SwitchParameter AllConstraints { get; set; }

    /// <summary>Returns every violating row instead of the first 200 per constraint (WITH ALL_ERRORMSGS).</summary>
    [Parameter]
    public SwitchParameter AllErrorMessages { get; set; }

    /// <summary>Suppresses informational DBCC messages (WITH NO_INFOMSGS).</summary>
    [Parameter]
    public SwitchParameter NoInformationalMessages { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $stringBuilder is built once in the source begin block and read every process record; carry it
    // forward so the process hop reads the same query the begin scope produced.
    private object? _stringBuilder;

    // $results is function-scoped in the source: it is assigned only inside the execute-ShouldProcess
    // gate but read inside the SEPARATE output-ShouldProcess gate. When the execute gate returns false
    // yet the output gate returns true (mixed interactive -Confirm across piped instances), the source
    // reads the PRIOR record's $results; a per-record hop resets it, so we carry it forward to reproduce
    // that leak bug-for-bug. Starts null (never assigned on record 1).
    private object? _resultsState;

    // Per-invocation token so the process carrier sentinel is distinguishable from real output.
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TestBound(nameof(AllConstraints)), TestBound(nameof(AllErrorMessages)),
            TestBound(nameof(NoInformationalMessages)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InvokeDbaDbDbccCheckConstraintBeginComplete"]?.Value))
            {
                _stringBuilder = UnwrapHopValue(item.Properties["StringBuilder"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InvokeDbaDbDbccCheckConstraintProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _resultsState = UnwrapHopValue(item.Properties["Results"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _stringBuilder, SqlInstance, SqlCredential, Database, Object, EnableException.ToBool(),
            _resultsState, this, _processToken, TestBound(nameof(Object)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    private const string BeginScript = """
param($__boundAllConstraints, $__boundAllErrorMessages, $__boundNoInformationalMessages, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundAllConstraints, $__boundAllErrorMessages, $__boundNoInformationalMessages)

    # Test-Bound replacement: the source keyed each WITH clause off whether the caller EXPLICITLY
    # bound each switch (a boundness check, not its value); module scope cannot see the caller's
    # bound set, so boundness is carried in as a flag per parameter.
    $withCount = 0
    $stringBuilder = New-Object System.Text.StringBuilder
    $null = $stringBuilder.Append("DBCC CHECKCONSTRAINTS(#options#)")
    if ($__boundAllConstraints) {
        $null = $stringBuilder.Append(" WITH ALL_CONSTRAINTS")
        $withCount++
    }
    if ($__boundAllErrorMessages) {
        if ($withCount -eq 0) {
            $null = $stringBuilder.Append(" WITH ALL_ERRORMSGS")
        } else {
            $null = $stringBuilder.Append(", ALL_ERRORMSGS")
        }
        $withCount++
    }
    if ($__boundNoInformationalMessages) {
        if ($withCount -eq 0) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        } else {
            $null = $stringBuilder.Append(", NO_INFOMSGS")
        }
    }

    [pscustomobject]@{ __InvokeDbaDbDbccCheckConstraintBeginComplete = $true; StringBuilder = $stringBuilder }
} $__boundAllConstraints $__boundAllErrorMessages $__boundNoInformationalMessages @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($StringBuilder, $SqlInstance, $SqlCredential, $Database, $Object, $EnableException, $results, $__realCmdlet, $__processToken, $__boundObject, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param($StringBuilder, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Database, [string]$Object, $EnableException, $results, $__realCmdlet, $__processToken, $__boundObject)

    foreach ($instance in $SqlInstance) {
        Write-Message -Message "Attempting Connection to $instance" -Level Verbose -FunctionName Invoke-DbaDbDbccCheckConstraint -ModuleName "dbatools"
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDbccCheckConstraint
        }

        $dbs = $server.Databases

        if ($Database) {
            $dbs = $dbs | Where-Object Name -In $Database
        }

        foreach ($db in $dbs) {
            Write-Message -Level Verbose -Message "Processing $db on $instance" -FunctionName Invoke-DbaDbDbccCheckConstraint -ModuleName "dbatools"

            if ($db.IsAccessible -eq $false) {
                Stop-Function -Message "The database $db is not accessible. Skipping." -Continue -FunctionName Invoke-DbaDbDbccCheckConstraint
            }

            try {
                $query = $StringBuilder.ToString()
                if ($__boundObject) {
                    if ($object -match '^\d+$') {
                        $query = $query.Replace('#options#', "$Object")
                    } else {
                        $query = $query.Replace('#options#', "'$Object'")
                    }
                } else {
                    $query = $query.Replace('(#options#)', "")
                }

                if ($__realCmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                    Write-Message -Message "Query to run: $query" -Level Verbose -FunctionName Invoke-DbaDbDbccCheckConstraint -ModuleName "dbatools"
                    $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                }
            } catch {
                Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue -FunctionName Invoke-DbaDbDbccCheckConstraint
            }

            if ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
                $output = $null
                if (($null -eq $results) -or ($results.GetType().Name -eq 'String') ) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Cmd          = $query.ToString()
                        Output       = $results
                        Table        = $null
                        Constraint   = $null
                        Where        = $null
                    }
                } elseif (($results.GetType().Name -eq 'Object[]') -or ($results.GetType().Name -eq 'DataRow')) {
                    foreach ($row in $results) {
                        if ($row.GetType().Name -eq 'String') {
                            $output = $row.ToString()
                        } else {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.Name
                                Cmd          = $query.ToString()
                                Output       = $output
                                Table        = $row[0]
                                Constraint   = $row[1]
                                Where        = $row[2]

                            }
                        }
                    }
                }
            }
        }
    }

    [pscustomobject]@{ __InvokeDbaDbDbccCheckConstraintProcessComplete = $__processToken; Results = $results }
} $StringBuilder $SqlInstance $SqlCredential $Database $Object $EnableException $results $__realCmdlet $__processToken $__boundObject @__commonParameters 3>&1 2>&1
""";
}
