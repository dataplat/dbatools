#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates database snapshots. Port of public/New-DbaDbSnapshot.ps1 (390 lines); the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. $InputObject is ValueFromPipeline, so process fires per record.
///
/// INTERRUPT CARRY IS LIVE. The -NameSuffix template guard at :164 is Stop-Function WITHOUT
/// -Continue, so it sets the module latch, and process opens with "if (Test-FunctionInterrupt)
/// { return }" at :190 - a bad template must silence every record. The latch does not survive
/// between hop invocations, so the begin hop reads it at Get-Variable -Scope 0 and carries it to C#,
/// which skips process. Measured in migration/logs/probe-20260718-latch-sentinel.
///
/// THE RISK ON THIS ROW IS $ConfirmPreference, AND IT IS A CLASS MY ACCUMULATOR DETECTOR CANNOT SEE.
/// Begin :154 does "if ($Force) { $ConfirmPreference = 'none' }", and the ShouldProcess gate is at
/// :289, in PROCESS. In the source those share one function scope, so -Force suppresses the prompt.
/// Across a hop, begin's scope dies with its invocation, so a naive port would silently STOP
/// suppressing the confirm prompt on a snapshot-creating command - the user passes -Force and gets
/// prompted anyway. migration/tools/Find-AccumulatorCarry.ps1 cannot flag this: it inspects "+="
/// targets, and this is a preference-variable assignment. Stated plainly rather than left implied,
/// because a tool's blind spots are part of its contract.
///
/// The process hop therefore re-establishes it in its preamble from $Force. That is provably
/// equivalent rather than approximate: begin's condition is exactly "if ($Force)", and :154 is the
/// FIRST statement of begin, so it always evaluates - there is no path on which begin sets it and
/// the same $Force would not.
///
/// That this works AT ALL through the compiled gate is measured, not assumed. The gate routes to
/// $__realCmdlet - the real C# cmdlet - and it was not obvious that a $ConfirmPreference assigned
/// inside a module-scoped scriptblock would be observed by it. A throwaway COMPILED probe settled
/// it: migration/logs/probe-20260718-force-confirmpref shows a real compiled cmdlet's ShouldProcess
/// DOES observe a $ConfirmPreference assigned inside the hop scriptblock, including across the
/// module session-state boundary the production hop actually uses, with controls that demonstrably
/// detected prompting (both no-Force controls threw).
///
/// TWO ORDINARY BEGIN-TO-PROCESS CARRIES:
///  - $DefaultSuffix (:158) is Get-Date evaluated ONCE in begin, and the source comment says it is
///    done there "for naming consistency". Process reads it at :263 and :309. Recomputing it per
///    record would give snapshots created in one pipeline DIFFERENT timestamps, breaking the
///    documented intent - so it carries rather than being re-derived.
///  - $NoSupportForSnap (:156), read at :228. Read-only.
///
/// NO CROSS-RECORD ACCUMULATOR. Find-AccumulatorCarry.ps1 reports seven "+=" sites ($message in
/// begin, $counter, $Notes, $hints) all reset in-block, so none survives a record boundary.
///
/// THE BEGIN HELPER IS DEAD CODE. Resolve-SnapshotError (:168-187) is defined in begin, and its only
/// appearance in process is a COMMENT at :378. It therefore rides verbatim inside the begin hop and
/// does NOT need recreating in the process hop - unlike New-DbaDacProfile (W2-142), whose begin
/// helpers were genuinely called from process. Checked rather than assumed from the shape.
///
/// SWITCHES CROSS AS SwitchParameter OBJECTS received UNTYPED, per B's combined rule. That matters
/// concretely here beyond the .IsPresent axis: process :192 does "$AllDatabases -eq $false", and
/// passing the OBJECT means the body compares exactly what the source compares. Marshaling to a
/// plain bool would change the operand type of a live comparison.
///
/// STREAMING, NOT BUFFERED (DEF-001): snapshots are created per database and emitted as they are
/// taken, so a buffered hop would discard the record of snapshots already created when a later
/// failure terminated the hop under -EnableException.
///
/// The one gate at :289 (spelled $PSCmdlet here, capitalised differently from other rows) routes to
/// $__realCmdlet. In-hop Stop-Function/Write-Message calls carry -FunctionName. There are no
/// Test-Bound and no .IsPresent sites. Implicit positions 0-7 are made explicit per the W2-071 law
/// and were confirmed against the exported baseline; the three switches carry none. Surface pinned
/// by migration/baselines/New-DbaDbSnapshot.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbSnapshot", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaDbSnapshotCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to snapshot.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Snapshot every eligible database.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>A fixed snapshot name; only valid for a single database.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Name { get; set; }

    /// <summary>A snapshot name template containing exactly one {0} placeholder.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? NameSuffix { get; set; }

    /// <summary>Directory the snapshot files are written to.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Suppress the confirmation prompt.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $DefaultSuffix and $NoSupportForSnap from begin; opaque to C#.
    private Hashtable? _beginState;
    // A bad -NameSuffix template silences every record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NameSuffix, Force, EnableException,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbSnapshotBegin"))
            {
                if (sentinel["__newDbaDbSnapshotBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        // Streaming, not buffered (DEF-001): snapshots are created and emitted per database, so a
        // buffered hop would drop the audit trail of snapshots already taken.
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, AllDatabases, Name, NameSuffix,
            Path, Force, InputObject, EnableException, _beginState, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced. Only edit is -FunctionName on the message calls.
    // The sentinel carries $DefaultSuffix (Get-Date evaluated ONCE here for naming consistency),
    // $NoSupportForSnap, and the interrupt latch read at Scope 0. The dead helper
    // Resolve-SnapshotError rides verbatim; process only mentions it in a comment.
    private const string BeginScript = """
param($NameSuffix, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$NameSuffix, $Force, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        $NoSupportForSnap = @('model', 'master', 'tempdb')
        # Evaluate the default suffix here for naming consistency
        $DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
        if ($NameSuffix.Length -gt 0) {
            #Validate if Name can be interpolated
            try {
                $null = $NameSuffix -f 'some_string'
            } catch {
                Stop-Function -Message "NameSuffix parameter must be a template only containing one parameter {0}" -ErrorRecord $_ -FunctionName New-DbaDbSnapshot
            }
        }

        function Resolve-SnapshotError($server) {
            $errHelp = ''
            $CurrentEdition = $server.Edition.ToLowerInvariant()
            $CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
            if ($server.Version.Major -lt 9) {
                $errHelp = 'Not supported before 2005'
            }
            if ($CurrentVersion -lt 12002000 -and $errHelp.Length -eq 0) {
                if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*') {
                    $errHelp = 'Supported only for Enterprise, Developer or Datacenter editions'
                }
            }
            $message = ""
            if ($errHelp.Length -gt 0) {
                $message += "Please make sure your version supports snapshots : ($errHelp)"
            } else {
                $message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
            }
            Write-Message -Level Warning -Message $message -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__ds = Get-Variable -Name DefaultSuffix -Scope 0 -ErrorAction Ignore
    $__ns = Get-Variable -Name NoSupportForSnap -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbSnapshotBegin = @{
        Interrupted      = [bool]($__iv -and $__iv.Value)
        DefaultSuffix    = $(if ($__ds) { $__ds.Value } else { $null })
        NoSupportForSnap = $(if ($__ns) { , @($__ns.Value) } else { , @() })
    } }
} $NameSuffix $Force $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so its early return exits only the body. Edits:
    // the one $PSCmdlet gate routes to $__realCmdlet, and -FunctionName on the message calls.
    //
    // THE PREAMBLE RE-ESTABLISHES $ConfirmPreference. Source begin :154 sets it from -Force, and the
    // gate that reads it is here in process; begin's hop scope died with its invocation, so without
    // this line -Force would silently stop suppressing the prompt. Equivalent by construction:
    // begin's condition is exactly "if ($Force)" and :154 is begin's first statement. That the
    // compiled gate observes it is measured - logs/probe-20260718-force-confirmpref.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllDatabases, $Name, $NameSuffix, $Path, $Force, $InputObject, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases, [string]$Name, [string]$NameSuffix, [string]$Path, $Force, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # source begin :154, re-established because begin's scope does not reach this hop
    if ($Force) { $ConfirmPreference = 'none' }
    # begin's once-evaluated naming state
    $DefaultSuffix    = $__beginState.DefaultSuffix
    $NoSupportForSnap = @($__beginState.NoSupportForSnap)

    . {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $Database -and $AllDatabases -eq $false) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -EnableException $EnableException -FunctionName New-DbaDbSnapshot
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDbSnapshot
            }
            #Checks for path existence, left the length test because test-bound wasn't working for some reason
            if ($Path.Length -gt 0) {
                if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                    Stop-Function -Message "$instance cannot access the directory $Path" -Target $instance -Continue -EnableException $EnableException -FunctionName New-DbaDbSnapshot
                }
            }

            if ($AllDatabases) {
                $dbs = $server.Databases
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $server.Databases | Where-Object { $ExcludeDatabase -notcontains $_.Name }
            }

            ## double check for gotchas
            foreach ($db in $dbs) {
                if ($db.IsMirroringEnabled) {
                    $InputObject += $db
                } elseif ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "$($db.name) is a snapshot, skipping" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                } elseif ($db.name -in $NoSupportForSnap) {
                    Write-Message -Level Warning -Message "$($db.name) snapshots are prohibited" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                } elseif ($db.IsAccessible -ne $true -and ($server.AvailabilityGroups | Where-Object Name -eq $db.AvailabilityGroupName).LocalReplicaRole -eq 'Secondary') {
                    # Readable secondaries are considered accessible.
                    # This accounts for every other valid state of an AG (e.g. a database in a Basic Availability Group is a valid target).
                    $InputObject += $db
                } elseif ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                } else {
                    $InputObject += $db
                }
            }

            if ($InputObject.Count -gt 1 -and $Name) {
                Stop-Function -Message "You passed the Name parameter that is fixed but selected multiple databases to snapshot: use the NameSuffix parameter" -Continue -EnableException $EnableException -FunctionName New-DbaDbSnapshot
            }
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # In case stuff is piped in
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $server not supported" -Continue -FunctionName New-DbaDbSnapshot
            }

            if ($NameSuffix.Length -gt 0) {
                $SnapName = $NameSuffix -f $db.Name
                if ($SnapName -eq $NameSuffix) {
                    #no interpolation, just append
                    $SnapName = '{0}{1}' -f $db.Name, $NameSuffix
                }
            } elseif ($Name.Length -gt 0) {
                $SnapName = $Name
            } else {
                $SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
            }
            if ($SnapName -in $server.Databases.Name) {
                Write-Message -Level Warning -Message "A database named $SnapName already exists, skipping" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                continue
            }
            # Refresh database and FileGroups collection to ensure SMO has populated data
            # This is especially important for AG secondary replicas where collections may not be auto-populated
            $db.Refresh()
            $db.FileGroups.Refresh()
            $all_FSD = $db.FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
            $all_MMO = $db.FileGroups | Where-Object FileGroupType -eq 'MemoryOptimizedDataFileGroup'
            $has_FSD = $all_FSD.Count -gt 0
            $has_MMO = $all_MMO.Count -gt 0
            if ($has_MMO) {
                Write-Message -Level Warning -Message "MEMORY_OPTIMIZED_DATA detected, snapshots are not possible" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                continue
            }
            if ($has_FSD -and $Force -eq $false) {
                Write-Message -Level Warning -Message "Filestream detected, skipping. You need to specify -Force. See Get-Help for details" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"
                continue
            }
            $snapType = "db snapshot"
            if ($has_FSD) {
                $snapType = "partial db snapshot"
            }
            If ($__realCmdlet.ShouldProcess($server, "Create $snapType $SnapName of $($db.Name)")) {
                $CustomFileStructure = @{ }
                $counter = 0
                foreach ($fg in $db.FileGroups) {
                    $CustomFileStructure[$fg.Name] = @()
                    if ($fg.FileGroupType -eq 'FileStreamDataFileGroup') {
                        Continue
                    }
                    foreach ($file in $fg.Files) {
                        $counter += 1
                        # Linux can't handle windows paths, so split it
                        $basename = [IO.Path]::GetFileNameWithoutExtension((Split-Path $file.FileName -Leaf))
                        $originalExtension = [IO.Path]::GetExtension((Split-Path $file.FileName -Leaf))
                        $basePath = Split-Path $file.FileName -Parent
                        # change path if specified
                        if ($Path.Length -gt 0) {
                            $basePath = $Path
                        }

                        # we need to avoid cases where basename is the same for multiple FG
                        $fName = [IO.Path]::Combine($basePath, ("{0}_{1}_{2:0000}_{3:000}{4}" -f $basename, $DefaultSuffix, (Get-Date).MilliSecond, $counter, $originalExtension))
                        # fixed extension is hardcoded as "ss", which seems a "de-facto" standard
                        $fName = [IO.Path]::ChangeExtension($fName, "ss")
                        Write-Message -Level Debug -Message "$fName" -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"

                        # change slashes for Linux, change slashes for Windows
                        if ($server.HostPlatform -eq 'Linux') {
                            $fName = $fName.Replace("\", "/")
                        } else {
                            $fName = $fName.Replace("/", "\")
                        }
                        $CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fName }
                    }
                }

                $SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $SnapName
                $SnapDB.DatabaseSnapshotBaseName = $db.Name

                foreach ($fg in $CustomFileStructure.Keys) {
                    $SnapFG = New-Object -TypeName Microsoft.SqlServer.Management.Smo.FileGroup $SnapDB, $fg
                    $SnapDB.FileGroups.Add($SnapFG)
                    foreach ($file in $CustomFileStructure[$fg]) {
                        $SnapFile = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DataFile $SnapFG, $file['name'], $file['filename']
                        $SnapDB.FileGroups[$fg].Files.Add($SnapFile)
                    }
                }

                # we're ready to issue a Create, but SMO is a little uncooperative here
                # there are cases we can manage and others we can't, and we need all the
                # info we can get both from testers and from users

                $sql = $SnapDB.Script()

                try {
                    $SnapDB.Create()
                    $server.Databases.Refresh()
                    Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                } catch {
                    try {
                        $server.Databases.Refresh()
                        if ($SnapName -notin $server.Databases.Name) {
                            # previous creation failed completely, snapshot is not there already
                            $null = $server.Query($sql[0])
                            $server.Databases.Refresh()
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        } else {
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        }

                        $Notes = @()
                        if ($db.ReadOnly -eq $true) {
                            $Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
                        }
                        if ($has_FSD) {
                            #Variable marked as unused by PSScriptAnalyzer
                            #$Status = 'Partial'
                            $Notes += 'Filestream groups are not viable for snapshot'
                        }
                        $Notes = $Notes -Join ';'

                        $hints = @("Executing these commands led to a partial failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }

                        Write-Message -Level Debug -Message ($hints -Join "`n") -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"

                        $SnapDB
                    } catch {
                        # Resolve-SnapshotError $server
                        $hints = @("Executing these commands led to a failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }
                        Write-Message -Level Debug -Message ($hints -Join "`n") -FunctionName New-DbaDbSnapshot -ModuleName "dbatools"

                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $SnapDB -Continue -FunctionName New-DbaDbSnapshot
                    }
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllDatabases $Name $NameSuffix $Path $Force $InputObject $EnableException $__beginState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
