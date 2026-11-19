#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoMailProfile = Microsoft.SqlServer.Management.Smo.Mail.MailProfile;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies an existing Database Mail profile.
/// </summary>
/// <remarks>
/// Completes the Database Mail profile family (New-/Get-/Remove-DbaDbMailProfile already ship; there was no
/// Set-). The duality resolution (Get-DbaDbMailProfile), the property Alter, the rename, the account and
/// principal association calls, the confirmation gates and the result-object shaping all run a dbatools
/// PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the engine
/// decides the observable details.
///
/// Description is the ONLY alterable property, and MailProfileBase.ScriptAlter emits nothing at all unless
/// Description is dirty, so the body never calls Alter() unless -Description was bound. The real value of
/// the command is account and principal management, which is NOT part of Alter() and is NOT atomic with it:
/// each association method executes its own T-SQL immediately, so a single invocation can partially succeed.
/// A true rollback is not achievable without inverse operations that can themselves fail, so the body
/// applies the property Alter() first, then the associations in a defined order, and reports precisely which
/// operations landed before any failure via a per-item warning - honest where a claimed rollback would not
/// be. -NewName is a Rename(), a distinct operation with its own ShouldProcess target.
///
/// Process-only duality: each SqlInstance's matching profiles are gathered into $InputObject (a VFP param
/// rebound per record, so the += stays within one record) and every profile is then updated. Every local is
/// per-iteration, so a single per-record hop reproduces the whole body with no cross-record sentinel.
///
/// The Test-Bound sites are replaced by lookups on this cmdlet's own MyInvocation.BoundParameters (passed as
/// $__bound), because Test-Bound reads the CALLER's $PSBoundParameters and inside the hop the positional
/// binding makes every parameter look bound. IsDefaultForPrincipal is marshaled as its SwitchParameter value
/// so the body's .IsPresent still resolves.
///
/// Output streams: each updated profile is emitted before a later profile's operation may Stop-Function
/// under -EnableException, so buffering would hide profiles that were actually changed.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact Low, no -Force). Surface
/// pinned by migration/designed/Set-DbaDbMailProfile.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbMailProfile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(SmoMailProfile))]
public sealed class SetDbaDbMailProfileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>One or more Database Mail profile names to modify.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? Profile { get; set; }

    /// <summary>Updates the documentation text describing the profile.</summary>
    [Parameter(Position = 3)]
    public string? Description { get; set; }

    /// <summary>Renames the profile.</summary>
    [Parameter(Position = 4)]
    public string? NewName { get; set; }

    /// <summary>MailProfile objects piped in from Get-DbaDbMailProfile.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public SmoMailProfile[]? InputObject { get; set; }

    /// <summary>One or more Database Mail account names to associate with the profile.</summary>
    [Parameter]
    public string[]? AddAccount { get; set; }

    /// <summary>The failover sequence number for the first added account; increments for the rest.</summary>
    [Parameter]
    public int AccountSequence { get; set; }

    /// <summary>One or more Database Mail account names to disassociate from the profile.</summary>
    [Parameter]
    public string[]? RemoveAccount { get; set; }

    /// <summary>One or more security principals to grant access to the profile.</summary>
    [Parameter]
    public string[]? AddPrincipal { get; set; }

    /// <summary>One or more security principals to revoke access from the profile.</summary>
    [Parameter]
    public string[]? RemovePrincipal { get; set; }

    /// <summary>Marks the profile as the default for each principal added with -AddPrincipal.</summary>
    [Parameter]
    public SwitchParameter IsDefaultForPrincipal { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Reproduce Test-Bound faithfully: this cmdlet's own bound parameters.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

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
        }, BodyScript,
            SqlInstance, SqlCredential, Profile, InputObject, Description, NewName,
            AddAccount, AccountSequence, RemoveAccount, AddPrincipal, RemovePrincipal, IsDefaultForPrincipal,
            EnableException.ToBool(), bound, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The Test-Bound sites map to $__bound.ContainsKey lookups; Stop-Function carries -FunctionName
    // Set-DbaDbMailProfile; $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Profile, $InputObject, $Description, $NewName, $AddAccount, $AccountSequence, $RemoveAccount, $AddPrincipal, $RemovePrincipal, $IsDefaultForPrincipal, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Profile, [Microsoft.SqlServer.Management.Smo.Mail.MailProfile[]]$InputObject, [string]$Description, [string]$NewName, [string[]]$AddAccount, [int]$AccountSequence, [string[]]$RemoveAccount, [string[]]$AddPrincipal, [string[]]$RemovePrincipal, $IsDefaultForPrincipal, $EnableException, $__bound, $__realCmdlet)
    if (-not $SqlInstance -and -not $InputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -Category InvalidArgument -FunctionName Set-DbaDbMailProfile
        return
    }
    if ($__bound.ContainsKey('IsDefaultForPrincipal') -and -not $__bound.ContainsKey('AddPrincipal')) {
        Stop-Function -Message "-IsDefaultForPrincipal is only meaningful together with -AddPrincipal" -Category InvalidArgument -FunctionName Set-DbaDbMailProfile
        return
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDbMailProfile -SqlInstance $instance -SqlCredential $SqlCredential -Profile $Profile -EnableException:$EnableException
    }

    foreach ($mailProfile in $InputObject) {
        $instanceName = $mailProfile.SqlInstance
        if (-not $instanceName) {
            $instanceName = $mailProfile.Parent.Parent.DomainInstanceName
        }

        $applied = @()
        $hasAlterWork = $__bound.ContainsKey('Description') -or $AddAccount -or $RemoveAccount -or $AddPrincipal -or $RemovePrincipal

        if ($hasAlterWork -and $__realCmdlet.ShouldProcess($instanceName, "Altering Database Mail profile $($mailProfile.Name)")) {
            try {
                # Description is the only alterable property; Alter() is a no-op emit unless it is dirty, so
                # only touch it when bound.
                if ($__bound.ContainsKey('Description')) {
                    $mailProfile.Description = $Description
                    $mailProfile.Alter()
                    $applied += "Description"
                }

                # Associations run after the property Alter, in a defined order. Each is its own immediate
                # statement and is not atomic with the others; a failure reports what already landed.
                foreach ($account in $RemoveAccount) {
                    $mailProfile.RemoveAccount($account)
                    $applied += "RemoveAccount:$account"
                }

                if ($AddAccount) {
                    if ($__bound.ContainsKey('AccountSequence')) {
                        $sequence = $AccountSequence
                    } else {
                        # Append after the current maximum failover sequence.
                        $sequence = 0
                        foreach ($row in $mailProfile.EnumAccounts().Rows) {
                            $current = [int]$row["SequenceNumber"]
                            if ($current -gt $sequence) { $sequence = $current }
                        }
                        $sequence++
                    }
                    foreach ($account in $AddAccount) {
                        $mailProfile.AddAccount($account, $sequence)
                        $applied += "AddAccount:$account($sequence)"
                        $sequence++
                    }
                }

                foreach ($principal in $RemovePrincipal) {
                    $mailProfile.RemovePrincipal($principal)
                    $applied += "RemovePrincipal:$principal"
                }

                foreach ($principal in $AddPrincipal) {
                    $mailProfile.AddPrincipal($principal, $IsDefaultForPrincipal.IsPresent)
                    $applied += "AddPrincipal:$principal"
                }
            } catch {
                $landed = if ($applied) { $applied -join ", " } else { "nothing" }
                Stop-Function -Message "Failure updating Database Mail profile $($mailProfile.Name) on $instanceName (applied before failure: $landed)" -Target $mailProfile -ErrorRecord $_ -Continue -FunctionName Set-DbaDbMailProfile
            }
        }

        if ($__bound.ContainsKey('NewName')) {
            if ($__realCmdlet.ShouldProcess($instanceName, "Renaming Database Mail profile $($mailProfile.Name) to $NewName")) {
                try {
                    $mailProfile.Rename($NewName)
                } catch {
                    Stop-Function -Message "Failure renaming Database Mail profile $($mailProfile.Name) to $NewName on $instanceName" -Target $mailProfile -ErrorRecord $_ -Continue -FunctionName Set-DbaDbMailProfile
                }
            }
        }

        $mailProfile.Refresh()
        $mailAccountNames = @($mailProfile.EnumAccounts().Rows | ForEach-Object { $_["AccountName"] })
        if ($mailAccountNames.Count -eq 0) {
            $mailAccountValue = $null
        } elseif ($mailAccountNames.Count -eq 1) {
            $mailAccountValue = $mailAccountNames[0]
        } else {
            $mailAccountValue = $mailAccountNames
        }

        Add-Member -Force -InputObject $mailProfile -MemberType NoteProperty -Name ComputerName -value $mailProfile.Parent.Parent.ComputerName
        Add-Member -Force -InputObject $mailProfile -MemberType NoteProperty -Name InstanceName -value $mailProfile.Parent.Parent.ServiceName
        Add-Member -Force -InputObject $mailProfile -MemberType NoteProperty -Name SqlInstance -value $mailProfile.Parent.Parent.DomainInstanceName
        Add-Member -Force -InputObject $mailProfile -MemberType NoteProperty -Name MailAccount -value $mailAccountValue
        $mailProfile | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, Description, ForceDeleteForActiveProfiles, IsBusyProfile, MailAccount
    }
} $SqlInstance $SqlCredential $Profile $InputObject $Description $NewName $AddAccount $AccountSequence $RemoveAccount $AddPrincipal $RemovePrincipal $IsDefaultForPrincipal $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
