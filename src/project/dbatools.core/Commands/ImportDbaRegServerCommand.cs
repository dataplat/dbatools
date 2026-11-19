#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports registered servers and server groups into a CMS from XML files, other CMS instances,
/// or custom objects. Port of public/Import-DbaRegServer.ps1 (W3-056). InputObject is
/// ValueFromPipeline, so each pipeline record rides ONE VERBATIM module hop in ProcessRecord
/// (GetDbaExtendedProtection precedent): the per-$SqlInstance loop, the $InputObject +=
/// Get-ChildItem file accumulation, and the per-$object import dispatch (RegisteredServer /
/// ServerGroup / FileInfo / CSV-like) all ride verbatim, so Add-DbaRegServer(Group),
/// Get-DbaRegServer(Group), and $reggroup.Import are decided by the engine exactly as the
/// function decided them. Surface pinned by migration/baselines/Import-DbaRegServer.json
/// (SqlInstance mandatory pos0; SqlCredential pos1; Path pos2 alias FullName; InputObject pos3
/// VFP; Group pos4; no SSP; no OutputType).
///
/// CARRIER (W2-071 class - BOUNDNESS, the opposite of W3-057's truthiness): the source guards
/// read Test-Bound -ParameterName Path/Group (presence of the bound parameter, NOT its value),
/// so they are carried as ContainsKey flags $__boundPath / $__boundGroup - matching the
/// source's own Test-Bound test line-by-line. Inside the hop, Test-Bound would see every
/// positionally-passed arg as bound, so the carrier substitution is mandatory. No truthiness
/// carrier here; the source never reads $PSBoundParameters values.
///
/// DEF-001: the per-file/per-group Stop-Function -Continue throws under -EnableException
/// mid-loop, and the loop emits imported RegisteredServer objects before it, so a buffered
/// foreach would lose them - delivered via InvokeScopedStreaming, the streaming graft.
///
/// DEF-006: the hop-level Write-Message carries -FunctionName Import-DbaRegServer -ModuleName
/// "dbatools"; every hop-level Stop-Function carries -FunctionName Import-DbaRegServer. No
/// helpers, so every site is hop-level. Not a stateful once-across-records op (each piped
/// object imports per its own record, matching the function world), so sentinel-carry=0.
/// </summary>
[Cmdlet("Import", "DbaRegServer")]
public sealed class ImportDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (the CMS to import into).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Path to XML files containing exported registered server configurations.</summary>
    [Parameter(Position = 2)]
    [Alias("FullName")]
    public string[]? Path { get; set; }

    /// <summary>Registered server / server group / custom objects to import.</summary>
    [Parameter(Position = 3, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>The target group within the CMS hierarchy for the imported servers.</summary>
    [Parameter(Position = 4)]
    public object? Group { get; set; }

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
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Path, InputObject, Group, EnableException.ToBool(),
            BoundPresence("Path"), BoundPresence("Group"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Carries a Test-Bound -ParameterName X guard (W2-071 class): BOUNDNESS of the
    /// parameter (ContainsKey), NOT the truthiness of its value.</summary>
    private object BoundPresence(string name) => MyInvocation.BoundParameters.ContainsKey(name);

    // PS: process body VERBATIM (single hop per record; no begin/end). Substitutions only: the
    // Test-Bound Path/Group guards become the carried $__boundPath / $__boundGroup ContainsKey
    // flags; hop-level Write-Message gains -FunctionName Import-DbaRegServer -ModuleName
    // "dbatools"; hop-level Stop-Function gains -FunctionName Import-DbaRegServer.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $InputObject, $Group, $EnableException, $__boundPath, $__boundGroup, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Path, [object[]]$InputObject, [object]$Group, $EnableException, $__boundPath, $__boundGroup, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        # Prep to import from file
        if ($__boundPath) {
            $InputObject += Get-ChildItem -Path $Path
        }
        if ($__boundGroup -and -not $__boundPath) {
            if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                $groupobject = $Group
            } else {
                $groupobject = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
            }
            if (-not $groupobject) {
                Stop-Function -Message "Group $Group cannot be found on $instance" -Target $instance -Continue -FunctionName Import-DbaRegServer
            }
        }

        foreach ($object in $InputObject) {
            if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {

                $groupexists = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $object.Parent.Name
                if (-not $groupexists) {
                    $groupexists = Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Parent.Name
                }
                Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupexists
            } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                foreach ($regserver in $object.RegisteredServers) {
                    $groupexists = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $regserver.Parent.Name
                    if (-not $groupexists) {
                        $groupexists = Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Parent.Name
                    }
                    Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Name -ServerName $regserver.ServerName -Description $regserver.Description -Group $groupexists
                }
            } elseif ($object -is [System.IO.FileInfo]) {
                if ($__boundGroup) {
                    if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        $reggroups = $Group
                    } else {
                        $reggroups = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                    }
                } else {
                    $reggroups = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
                }

                foreach ($file in $object) {
                    if (-not (Test-Path -Path $file)) {
                        Stop-Function -Message "$file cannot be found" -Target $file -Continue -FunctionName Import-DbaRegServer
                    }

                    foreach ($reggroup in $reggroups) {
                        try {
                            Write-Message -Level Verbose -Message "Importing $file to $($reggroup.Name) on $instance" -FunctionName Import-DbaRegServer -ModuleName "dbatools"
                            $urnlist = $reggroup.RegisteredServers.Urn.Value
                            $reggroup.Import($file.FullName)
                            Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential | Where-Object { $_.Urn.Value -notin $urnlist }
                        } catch {
                            Stop-Function -Message "Failure attempting to import $file to $instance" -ErrorRecord $_ -Continue -FunctionName Import-DbaRegServer
                        }
                    }
                }
            } else {
                if (-not $object.ServerName) {
                    Stop-Function -Message "Property 'ServerName' not found in InputObject. No servers added." -Continue -FunctionName Import-DbaRegServer
                }

                if (-not $__boundGroup) {
                    Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $object.Group
                } else {
                    Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupobject
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Path $InputObject $Group $EnableException $__boundPath $__boundGroup $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
