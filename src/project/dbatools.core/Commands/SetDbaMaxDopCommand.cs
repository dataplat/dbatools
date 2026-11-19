#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets Max Degree of Parallelism at instance or database scope. Port of
/// public/Set-DbaMaxDop.ps1 (W3-093). WHOLE-RECORD verbatim hop - per-element is
/// INELIGIBLE: $InputObject is destructively REASSIGNED (filtered) inside the instance
/// loop, so instance A's filtering shapes instance B's row set (cross-element state by
/// design). VFP-LOCAL CLASSIFICATION TABLE: $dbScopedConfiguration is assigned
/// unconditionally at record top; $instances/$server/$row/$results per iteration;
/// $UseRecommended is a pure function of the bound MaxDop (begin line riding at hop
/// top, idempotent); $resetDatabases is NEVER ASSIGNED anywhere (the W3-079
/// undeclared-variable class - reads null, the else branch always runs; preserved
/// verbatim); $InputObject reassignments are plain assignments (no +=) and the param
/// rebinds per piped record = no cross-record accumulation; NO local crosses records =
/// no sentinel. DUAL VFP mirrored in source declaration order (SqlInstance
/// DbaInstanceParameter[] first, InputObject SCALAR PSObject later) so pipeline
/// binding resolves identically - a piped Test-DbaMaxDop row binds InputObject per
/// record. The NINE Test-Bound calls read the FUNCTION's $psboundparameters via caller
/// -scope lookup and CANNOT ride the hop; each is substituted with carried TestBound
/// flags reproducing the exact Min/Max/-Not counting semantics (mapping documented at
/// each site). Gates route to the REAL cmdlet ($Pscmdlet -> $__realCmdlet, ConfirmImpact
/// Medium; no Force/ConfirmPreference convention = no transplant, no hold exposure).
/// QUIRKS verbatim: output objects are built and emitted OUTSIDE the ShouldProcess
/// gates (only Alter() is gated - -WhatIf emits rows carrying the would-be values and
/// mutates the in-memory SMO/row objects without persisting); Add-Member -Force
/// mutates the PIPED object visibly to the caller; Test-DbaMaxDop is invoked WITHOUT
/// -EnableException regardless of the caller's EE. NO WarningAction carrier (codex
/// W3-005 r3). Surface pinned by migration/baselines/Set-DbaMaxDop.json (implicit
/// positions 0-5, AllDatabases Alias All, InputObject scalar PSObject pos5 VFP,
/// MaxDop int pos4 default -1 with PsIntCast per W1-043).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaMaxDop", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaMaxDopCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Database(s) to set at database scope (SQL 2016+).</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The MAXDOP value; -1 (default) applies the recommended value.</summary>
    [Parameter(Position = 4)]
    [PsIntCast]
    public int MaxDop { get; set; } = -1;

    /// <summary>Test-DbaMaxDop output to act on.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public PSObject? InputObject { get; set; }

    /// <summary>Applies the database-scoped setting to all supported databases.</summary>
    [Parameter]
    [Alias("All")]
    public SwitchParameter AllDatabases { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, MaxDop, InputObject,
            AllDatabases.ToBool(), EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            TestBound(nameof(Database)), TestBound(nameof(ExcludeDatabase)),
            TestBound(nameof(AllDatabases)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin line + ENTIRE process body VERBATIM per record inside a dot-sourced
    // block (two validation early returns). Substitutions only: $Pscmdlet ->
    // $__realCmdlet on the two gates, explicit -FunctionName Set-DbaMaxDop on
    // Stop-Function/Write-Message at hop-frame level (W1-090), and each Test-Bound call
    // replaced by its exact carried-flag equivalent (Min/Max counting + -Not XOR,
    // mapping in comments at each site). Everything else - the destructive $InputObject
    // filters, the undeclared $resetDatabases read, the ungated output emission, the
    // Add-Member -Force caller-visible mutation - rides as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $MaxDop, $InputObject, $AllDatabases, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundExcludeDatabase, $__boundAllDatabases, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [int]$MaxDop, [PSCustomObject]$InputObject, $AllDatabases, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundExcludeDatabase, $__boundAllDatabases, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($MaxDop -eq -1) {
        $UseRecommended = $true
    }

    . {
        # Test-Bound -Min 2 -ParameterName Database, AllDatabases, ExcludeDatabase
        if ((([int][bool]$__boundDatabase) + ([int][bool]$__boundAllDatabases) + ([int][bool]$__boundExcludeDatabase)) -ge 2) {
            Stop-Function -Category InvalidArgument -Message "-Database, -AllDatabases and -ExcludeDatabase are mutually exclusive. Please choose only one." -FunctionName Set-DbaMaxDop
            return
        }

        # (Test-Bound -ParameterName SqlInstance, InputObject -not) = NEITHER bound
        if ((-not ($__boundSqlInstance -or $__boundInputObject))) {
            Stop-Function -Category InvalidArgument -Message "Please provide either the SqlInstance or InputObject." -FunctionName Set-DbaMaxDop
            return
        }

        $dbScopedConfiguration = $false

        # (Test-Bound -Not -ParameterName InputObject)
        if ((-not $__boundInputObject)) {
            $InputObject = Test-DbaMaxDop -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Verbose:$false
        } elseif ($null -eq $InputObject.SqlInstance) {
            $InputObject = Test-DbaMaxDop -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Verbose:$false
        }

        $InputObject | Add-Member -Force -NotePropertyName PreviousInstanceMaxDopValue -NotePropertyValue 0
        $InputObject | Add-Member -Force -NotePropertyName PreviousDatabaseMaxDopValue -NotePropertyValue 0

        #If we have servers 2016 or higher we will have a row per database plus the instance level, getting unique we only run one time per instance
        $instances = $InputObject | Select-Object SqlInstance -Unique | Select-Object -ExpandProperty SqlInstance

        foreach ($instance in $instances) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaMaxDop
            }

            if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $instance. Skipping." -Category PermissionDenied -Target $instance -Continue -FunctionName Set-DbaMaxDop
            }

            if ($server.versionMajor -ge 13) {
                Write-Message -Level Verbose -Message "Server '$instance' supports Max DOP configuration per database." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"

                # (Test-Bound -ParameterName Database, ExcludeDatabase -not) = NEITHER bound
                if ((-not ($__boundDatabase -or $__boundExcludeDatabase))) {
                    #Set at instance level
                    $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                } else {
                    $dbScopedConfiguration = $true

                    # (Test-Bound -Not -ParameterName AllDatabases) -and (Test-Bound -ParameterName Database)
                    if ((-not $__boundAllDatabases) -and ($__boundDatabase)) {
                        $InputObject = $InputObject | Where-Object { $_.Database -in $Database }
                    # (Test-Bound -Not -ParameterName AllDatabases) -and (Test-Bound -ParameterName ExcludeDatabase)
                    } elseif ((-not $__boundAllDatabases) -and ($__boundExcludeDatabase)) {
                        $InputObject = $InputObject | Where-Object { $_.Database -notin $ExcludeDatabase }
                    } else {
                        # (Test-Bound -ParameterName AllDatabases)
                        if ($__boundAllDatabases) {
                            $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -ne "N/A" }
                        } else {
                            $InputObject = $InputObject | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                            $dbScopedConfiguration = $false
                        }
                    }
                }
            } else {
                # (Test-Bound -ParameterName database) -or (Test-Bound -ParameterName AllDatabases)
                if (($__boundDatabase) -or ($__boundAllDatabases)) {
                    Write-Message -Level Warning -Message "Server '$instance' (v$($server.versionMajor)) does not support Max DOP configuration at the database level. Remember that this option is only available from SQL Server 2016 (v13). Run the command again without using database related parameters. Skipping." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                    Continue
                }
            }

            foreach ($row in $InputObject | Where-Object { $_.SqlInstance -eq $instance }) {
                if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.CurrentInstanceMaxDop) -and !($dbScopedConfiguration)) {
                    Write-Message -Level Verbose -Message "$instance is configured properly. No change required." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                    Continue
                }

                if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.DatabaseMaxDop) -and $dbScopedConfiguration) {
                    Write-Message -Level Verbose -Message "Database $($row.Database) on $instance is configured properly. No change required." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                    Continue
                }

                $row.PreviousInstanceMaxDopValue = $row.CurrentInstanceMaxDop

                try {
                    if ($UseRecommended) {
                        if ($dbScopedConfiguration) {
                            $row.PreviousDatabaseMaxDopValue = $row.DatabaseMaxDop

                            if ($resetDatabases) {
                                Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP to $($row.DatabaseMaxDop)." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                                $server.Databases["$($row.Database)"].MaxDop = $row.DatabaseMaxDop
                            } else {
                                Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                                $server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
                                $row.DatabaseMaxDop = $row.RecommendedMaxDop
                            }

                        } else {
                            Write-Message -Level Verbose -Message "Changing $server SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $($row.RecommendedMaxDop)." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                            $server.Configuration.MaxDegreeOfParallelism.ConfigValue = $row.RecommendedMaxDop
                            $row.CurrentInstanceMaxDop = $row.RecommendedMaxDop
                        }
                    } else {
                        if ($dbScopedConfiguration) {
                            $row.PreviousDatabaseMaxDopValue = $row.DatabaseMaxDop

                            Write-Message -Level Verbose -Message "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $MaxDop." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                            $server.Databases["$($row.Database)"].MaxDop = $MaxDop
                            $row.DatabaseMaxDop = $MaxDop
                        } else {
                            Write-Message -Level Verbose -Message "Changing $instance SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $MaxDop." -FunctionName Set-DbaMaxDop -ModuleName "dbatools"
                            $server.Configuration.MaxDegreeOfParallelism.ConfigValue = $MaxDop
                            $row.CurrentInstanceMaxDop = $MaxDop
                        }
                    }

                    if ($dbScopedConfiguration) {
                        if ($__realCmdlet.ShouldProcess($row.Database, "Setting max dop on database")) {
                            $server.Databases["$($row.Database)"].Alter()
                        }
                    } else {
                        if ($__realCmdlet.ShouldProcess($instance, "Setting max dop on instance")) {
                            $server.Configuration.Alter()
                        }
                    }

                    $results = [PSCustomObject]@{
                        ComputerName                = $server.ComputerName
                        InstanceName                = $server.ServiceName
                        SqlInstance                 = $server.DomainInstanceName
                        InstanceVersion             = $row.InstanceVersion
                        Database                    = $row.Database
                        DatabaseMaxDop              = $row.DatabaseMaxDop
                        CurrentInstanceMaxDop       = $row.CurrentInstanceMaxDop
                        RecommendedMaxDop           = $row.RecommendedMaxDop
                        PreviousDatabaseMaxDopValue = $row.PreviousDatabaseMaxDopValue
                        PreviousInstanceMaxDopValue = $row.PreviousInstanceMaxDopValue
                    }

                    if ($dbScopedConfiguration) {
                        Select-DefaultView -InputObject $results -Property InstanceName, Database, PreviousDatabaseMaxDopValue, @{
                            name = "CurrentDatabaseMaxDopValue"; expression = {
                                $_.DatabaseMaxDop
                            }
                        }
                    } else {
                        Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, PreviousInstanceMaxDopValue, CurrentInstanceMaxDop
                    }
                } catch {
                    Stop-Function -Message "Could not modify Max Degree of Parallelism for $server." -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaMaxDop
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $MaxDop $InputObject $AllDatabases $EnableException $__boundSqlInstance $__boundInputObject $__boundDatabase $__boundExcludeDatabase $__boundAllDatabases $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
