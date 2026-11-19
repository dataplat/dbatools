#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Attaches database files to an instance. Port of public/Mount-DbaDatabase.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop per record (SqlInstance is Mandatory and ValueFromPipeline).
///
/// CROSS-RECORD CARRY, and unusually this one is unambiguous. Two PARAMETERS are mutated by the
/// body: $DatabaseOwner (replaced with the id-1 login, or "sa", when the supplied owner is not a
/// login on the server) and $FileStructure (rebuilt from backup history when the caller did not
/// supply one). Neither is a pipeline parameter, so the binder never rewrites them per record and
/// the source's function-scope variables keep those mutations for every later record - a second
/// piped instance starts with the owner the FIRST instance resolved. That is a source quirk,
/// reproduced not fixed. Because neither parameter can rebind, no detection is needed: the hop
/// simply prefers carried state when it exists over the bound parameter value. (Contrast
/// Invoke-DbaDbShrink, where the mutated $InputObject is ITSELF pipeline-bound, which is what made
/// its carry undecidable and forced a documented divergence.)
///
/// $FileStructure's carry is in practice inert - when it was not bound the body rebuilds it for
/// every database, and when it was bound the body never touches it - but it is carried anyway
/// because that costs nothing and does not rely on the inertness argument holding.
///
/// TEST-BOUND NEVER RIDES A HOP: "Test-Bound -Parameter FileStructure" tests what the CALLER bound,
/// which is a static fact for the whole invocation, so it becomes a carried flag. Note this is
/// deliberately NOT the same question as "has $FileStructure been assigned" - the flag stays false
/// for every record even after the body assigns the variable, exactly as the source's Test-Bound
/// does, which is what makes the rebuild happen per database rather than only once.
///
/// The single $Pscmdlet.ShouldProcess gate routes to the real cmdlet via $__realCmdlet. No
/// interrupt is carried: the source has no Test-FunctionInterrupt, and although the final
/// Stop-Function omits -Continue (so it does set the module flag), nothing in this command ever
/// reads it - reproducing a flag no one reads would be machinery for its own sake.
///
/// The module-level command alias Attach-DbaDatabase is NOT declared as a class [Alias]: it lives
/// in dbatools.psd1/psm1 AliasesToExport and resolves by name post-flip, exactly as
/// Detach-DbaDatabase does for Dismount-DbaDatabase. An isolated-assembly surface check will report
/// it "removed" - that is a harness artifact of loading the DLL without the module, not a port gap.
/// Surface pinned by migration/baselines/Mount-DbaDatabase.json.
/// </summary>
[Cmdlet(VerbsData.Mount, "DbaDatabase", SupportsShouldProcess = true)]
public sealed class MountDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to attach.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The database files to attach; rebuilt from backup history when omitted.</summary>
    [Parameter(Position = 3)]
    public System.Collections.Specialized.StringCollection? FileStructure { get; set; }

    /// <summary>The login to set as database owner; falls back to the id-1 login or "sa".</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? DatabaseOwner { get; set; }

    /// <summary>SMO attach option.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("None", "RebuildLog", "EnableBroker", "NewBroker", "ErrorBrokerConversations")]
    [PsStringCast]
    public string AttachOption { get; set; } = "None";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The two body-mutated parameters, carried across records (opaque - never interpreted in C#).
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__mountDbaDatabaseState"))
            {
                _state = sentinel["__mountDbaDatabaseState"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, FileStructure, DatabaseOwner, AttachOption,
            EnableException.ToBool(), _state, this,
            MyInvocation.BoundParameters.ContainsKey("FileStructure"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM per record, dot-sourced. Edits: Test-Bound -> the carried
    // $__boundFileStructure flag (what the CALLER bound, static for the invocation), $Pscmdlet ->
    // $__realCmdlet on the one gate, and -FunctionName on the five Stop-Function calls. The two
    // body-mutated parameters restore from the carry at the top and are snapshotted at the end, so
    // a later piped instance sees the owner an earlier one resolved - the source's behavior.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileStructure, $DatabaseOwner, $AttachOption, $EnableException, $__state, $__realCmdlet, $__boundFileStructure, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [System.Collections.Specialized.StringCollection]$FileStructure, [string]$DatabaseOwner, [string]$AttachOption, $EnableException, $__state, $__realCmdlet, $__boundFileStructure, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Restore the two body-mutated parameters from an earlier record. Neither is pipeline-bound, so
    # the binder never rewrites them and the source's function-scope values persist unconditionally.
    if ($null -ne $__state) {
        if ($__state.DatabaseOwnerAssigned) { $DatabaseOwner = $__state.DatabaseOwner }
        if ($__state.FileStructureAssigned) { $FileStructure = $__state.FileStructure }
    }

    . {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Mount-DbaDatabase
            }

            if (-not $server.Logins.Item($DatabaseOwner)) {
                try {
                    $DatabaseOwner = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
                } catch {
                    $DatabaseOwner = "sa"
                }
            }

            foreach ($db in $database) {

                if ($server.Databases[$db]) {
                    Stop-Function -Message "$db is already attached to $server." -Target $db -Continue -FunctionName Mount-DbaDatabase
                }

                if (-Not ($__boundFileStructure)) {
                    $backuphistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $db -Type Full | Sort-Object End -Descending | Select-Object -First 1

                    if (-not $backuphistory) {
                        $message = "Could not enumerate backup history to automatically build FileStructure. Rerun the command and provide the filestructure parameter."
                        Stop-Function -Message $message -Target $db -Continue -FunctionName Mount-DbaDatabase
                    }

                    $backupfile = $backuphistory.Path[0]
                    $filepaths = (Read-DbaBackupHeader -SqlInstance $server -FileList -Path $backupfile).PhysicalName | Select-Object -Unique

                    $FileStructure = New-Object System.Collections.Specialized.StringCollection
                    foreach ($file in $filepaths) {
                        $exists = Test-DbaPath -SqlInstance $server -Path $file
                        if (-not $exists) {
                            $message = "Could not find the files to build the FileStructure. Rerun the command and provide the FileStructure parameter."
                            Stop-Function -Message $message -Target $file -Continue -FunctionName Mount-DbaDatabase
                        }

                        $null = $FileStructure.Add($file)
                    }
                }

                If ($__realCmdlet.ShouldProcess($server, "Attaching $Database with $DatabaseOwner as database owner and $AttachOption as attachoption")) {
                    try {
                        $server.AttachDatabase($db, $FileStructure, $DatabaseOwner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::$AttachOption)

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db
                            AttachResult  = "Success"
                            AttachOption  = $AttachOption
                            FileStructure = $FileStructure
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -FunctionName Mount-DbaDatabase
                    }
                }
            }
        }
    }

    $__do = Get-Variable -Name DatabaseOwner -Scope 0 -ErrorAction Ignore
    $__fs = Get-Variable -Name FileStructure -Scope 0 -ErrorAction Ignore
    @{ __mountDbaDatabaseState = @{ DatabaseOwnerAssigned = [bool]$__do; DatabaseOwner = $(if ($__do) { $__do.Value }); FileStructureAssigned = [bool]$__fs; FileStructure = $(if ($__fs) { $__fs.Value }) } }
} $SqlInstance $SqlCredential $Database $FileStructure $DatabaseOwner $AttachOption $EnableException $__state $__realCmdlet $__boundFileStructure $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
