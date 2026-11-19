#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a new Database Mail profile.
/// </summary>
/// <remarks>
/// The instance connection, the existing-profile lookup, the create/add-account logic, the confirmation
/// gate, and the result-object shaping all run the original dbatools PowerShell body inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// SqlInstance binds from the pipeline; the body loops the instances and creates/updates a profile per
/// instance. One local spans the pipeline in the source's shared process scope: $profileObj. The source
/// never resets it at the top of the loop, and it is only assigned inside the create / add-account
/// branches; a record (or a later instance) that declines ShouldProcess (-WhatIf) or takes a
/// Stop-Function path leaves $profileObj holding the PREVIOUS record's profile, which the trailing
/// "if ($profileObj)" then re-stamps with the current server's note-properties and re-emits. That
/// cross-record leak is source behavior; a per-record hop scope would reset it, so $profileObj is carried
/// record-to-record via a sentinel (C# field seeded into the hop top, re-emitted at the end). The initial
/// state is null (the source's unassigned $profileObj), which the C# field default already provides, so no
/// first-vs-carried flag is needed. $MailAccountPriority is NOT carried: the source's
/// "if (!$MailAccountPriority) { $MailAccountPriority = 1 }" is idempotent and value-preserving, so a
/// per-record recompute equals the carried value.
///
/// Output streams: each created/updated profile is emitted before a later instance may Stop-Function or
/// throw under -EnableException, so buffering would hide profiles that were actually created.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact Low, no -Force).
/// Surface pinned by migration/baselines/New-DbaDbMailProfile.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbMailProfile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbMailProfileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name for the new Database Mail profile.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [Alias("Name")]
    [PsStringCast]
    public string Profile { get; set; } = null!;

    /// <summary>A description explaining the purpose of the Database Mail profile.</summary>
    [Parameter(Position = 3)]
    public string? Description { get; set; }

    /// <summary>An existing Database Mail account to associate with this profile during creation.</summary>
    [Parameter(Position = 4)]
    public string? MailAccountName { get; set; }

    /// <summary>The priority of the associated mail account within the profile (1 is highest).</summary>
    // No PsIntCast: that transform attribute is not present in this satellite, and inventing one would be
    // an improvised transform (DEF-004 discipline: flag gaps, do not improvise). The source's script [int]
    // binds "-MailAccountPriority $null" to 0; a compiled int refuses it. That bind-time edge is an UNPROBED
    // gap flagged for A, not fixed here - the surface baseline type (System.Int32) matches either way.
    [Parameter(Position = 5)]
    public int MailAccountPriority { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // $profileObj carried across records: the source keeps it in the shared process scope and never resets
    // it, so a record that does not assign it re-emits the prior record's object. Null-init matches the
    // source's unassigned first-record state, so no first-vs-carried flag is needed.
    private object? _profileObj;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbMailProfileState"))
            {
                if (sentinel["__newDbaDbMailProfileState"] is Hashtable state)
                {
                    _profileObj = state["ProfileObj"];
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Profile, Description, MailAccountName, MailAccountPriority,
            EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("MailAccountName"),
            MyInvocation.BoundParameters.ContainsKey("Description"),
            _profileObj, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, the
    // two Test-Bound -ParameterName sites -> carried $__boundMailAccountName / $__boundDescription flags, and
    // -FunctionName New-DbaDbMailProfile on the direct Stop-Function sites. $profileObj is seeded from the
    // carried value at the top and re-emitted in a sentinel at the end so the source's cross-record leak of
    // that local is reproduced.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Profile, $Description, $MailAccountName, $MailAccountPriority, $EnableException, $__boundMailAccountName, $__boundDescription, $__carriedProfileObj, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Profile, [string]$Description, [string]$MailAccountName, [int]$MailAccountPriority, $EnableException, $__boundMailAccountName, $__boundDescription, $__carriedProfileObj, $__realCmdlet)
    # Seed the carried cross-record state (source keeps $profileObj in the shared process scope, never reset).
    $profileObj = $__carriedProfileObj
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDbMailProfile
        }

        # Check if profile already exists
        $existingProfile = $server.Mail.Profiles | Where-Object Name -eq $Profile

        if ($existingProfile) {
            # Profile exists, just add the account if specified
            if ($__boundMailAccountName) {
                if ($__realCmdlet.ShouldProcess($instance, "Adding account $MailAccountName to existing db mail profile $Profile")) {
                    try {
                        if (!$MailAccountPriority) {
                            $MailAccountPriority = 1
                        }
                        $existingProfile.AddAccount($MailAccountName, $MailAccountPriority)
                        $profileObj = $existingProfile
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaDbMailProfile
                    }
                }
            } else {
                Stop-Function -Message "Profile $Profile already exists on $instance. Use MailAccountName parameter to add an account to the existing profile." -Continue -FunctionName New-DbaDbMailProfile
            }
        } else {
            # Profile doesn't exist, create it
            if ($__realCmdlet.ShouldProcess($instance, "Creating new db mail profile called $Profile")) {
                try {
                    $profileObj = New-Object Microsoft.SqlServer.Management.SMO.Mail.MailProfile $server.Mail, $Profile
                    if ($__boundDescription) {
                        $profileObj.Description = $Description
                    }
                    $profileObj.Create()
                    if ($__boundMailAccountName) {
                        if (!$MailAccountPriority) {
                            $MailAccountPriority = 1
                        }
                        $profileObj.AddAccount($MailAccountName, $MailAccountPriority) # sequenceNumber correlates to "Priority" when associating a db mail Account to a db mail Profile
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaDbMailProfile
                }
            }
        }

        if ($profileObj) {
            Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

            $profileObj | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, Description, IsBusyProfile
        }
    }

    @{ __newDbaDbMailProfileState = @{ ProfileObj = $profileObj } }
} $SqlInstance $SqlCredential $Profile $Description $MailAccountName $MailAccountPriority $EnableException $__boundMailAccountName $__boundDescription $__carriedProfileObj $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
