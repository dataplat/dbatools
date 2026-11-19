#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;
using SmoMailAccount = Microsoft.SqlServer.Management.Smo.Mail.MailAccount;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies an existing Database Mail account.
/// </summary>
/// <remarks>
/// The mutually-exclusive-credentials guard, the account lookup (Get-DbaDbMailAccount), the property and
/// mail-server updates, the Alter calls, and the result-object shaping all run the original dbatools
/// PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the engine
/// decides the observable details.
///
/// Process-only. InputObject is the only pipeline-bound parameter; the body gathers each SqlInstance's
/// accounts into $InputObject (a VFP param rebound per record, so the += stays within one record) and then
/// updates every account. Every other local is per-iteration, so a single per-record hop reproduces the
/// whole body with no cross-record sentinel. The top guard's Stop-Function has no -Continue - it sets the
/// function-scope interrupt and returns - but nothing in this function reads Test-FunctionInterrupt, so the
/// interrupt is inert; the return (which exits the hop scriptblock) is what matters, and under
/// -EnableException it throws instead (re-thrown to terminate the record).
///
/// The many Test-Bound sites are replaced by lookups on this cmdlet's own MyInvocation.BoundParameters
/// (passed as $__bound), because Test-Bound reads the CALLER's $PSBoundParameters and inside the hop the
/// caller is the inner scriptblock, whose positional binding makes every parameter look bound. Single-name
/// Test-Bound maps to $__bound.ContainsKey(name); the one multi-name site (UserName, Password) maps to an
/// -or of both keys (Test-Bound's default is "at least one bound"). EnableSSL and UseDefaultCredentials are
/// marshaled as their SwitchParameter values (not bools) so the body's .IsPresent still resolves.
///
/// Output streams: each updated account is emitted before a later account's Alter may throw terminating
/// under -EnableException (the catch's Stop-Function has no -Continue effect under -EnableException), so
/// buffering would hide accounts that were actually changed (DEF-001).
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact Medium, no -Force).
/// Surface pinned by migration/baselines/Set-DbaDbMailAccount.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbMailAccount", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaDbMailAccountCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>One or more Database Mail account names to modify.</summary>
    [Parameter(Position = 2)]
    public string[]? Account { get; set; }

    /// <summary>MailAccount objects piped in from Get-DbaDbMailAccount.</summary>
    [Parameter(Position = 3, ValueFromPipeline = true)]
    public SmoMailAccount[]? InputObject { get; set; }

    /// <summary>Updates the friendly name that appears in the 'From' field of outgoing emails.</summary>
    [Parameter(Position = 4)]
    public string? DisplayName { get; set; }

    /// <summary>Updates the documentation text describing the account.</summary>
    [Parameter(Position = 5)]
    public string? Description { get; set; }

    /// <summary>Updates the sender email address for outgoing messages.</summary>
    [Parameter(Position = 6)]
    public string? EmailAddress { get; set; }

    /// <summary>Updates the alternate reply-to email address.</summary>
    [Parameter(Position = 7)]
    public string? ReplyToAddress { get; set; }

    /// <summary>Renames or replaces the SMTP server hostname for the account.</summary>
    [Parameter(Position = 8)]
    public string? NewMailServerName { get; set; }

    /// <summary>Updates the TCP port used to connect to the SMTP server.</summary>
    [Parameter(Position = 9)]
    [ValidateRange(1, 65535)]
    public int Port { get; set; }

    /// <summary>Enables or disables SSL/TLS encryption for the SMTP connection.</summary>
    [Parameter]
    public SwitchParameter EnableSSL { get; set; }

    /// <summary>Enables or disables Windows integrated authentication for SMTP.</summary>
    [Parameter]
    public SwitchParameter UseDefaultCredentials { get; set; }

    /// <summary>Updates the username for SMTP authentication.</summary>
    [Parameter(Position = 10)]
    public string? UserName { get; set; }

    /// <summary>Updates the password for SMTP authentication as a SecureString.</summary>
    [Parameter(Position = 11)]
    public SecureString? Password { get; set; }

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
            SqlInstance, SqlCredential, Account, InputObject, DisplayName, Description, EmailAddress,
            ReplyToAddress, NewMailServerName, Port, EnableSSL, UseDefaultCredentials, UserName, Password,
            EnableException.ToBool(), bound, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, the
    // Test-Bound sites -> $__bound.ContainsKey lookups (single name; the UserName/Password site -> an -or of
    // both keys), and -FunctionName Set-DbaDbMailAccount on the direct Stop-Function sites.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Account, $InputObject, $DisplayName, $Description, $EmailAddress, $ReplyToAddress, $NewMailServerName, $Port, $EnableSSL, $UseDefaultCredentials, $UserName, $Password, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Account, [Microsoft.SqlServer.Management.Smo.Mail.MailAccount[]]$InputObject, [string]$DisplayName, [string]$Description, [string]$EmailAddress, [string]$ReplyToAddress, [string]$NewMailServerName, [int]$Port, $EnableSSL, $UseDefaultCredentials, [string]$UserName, [System.Security.SecureString]$Password, $EnableException, $__bound, $__realCmdlet)
    if ($UseDefaultCredentials.IsPresent -and ($__bound.ContainsKey('UserName') -or $__bound.ContainsKey('Password'))) {
        Stop-Function -Category InvalidArgument -Message "You cannot specify -UseDefaultCredentials with -UserName or -Password." -FunctionName Set-DbaDbMailAccount
        return
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDbMailAccount -SqlInstance $instance -SqlCredential $SqlCredential -Account $Account -EnableException:$EnableException
    }

    foreach ($mailAccount in $InputObject) {
        $instanceName = $mailAccount.SqlInstance
        if (-not $instanceName) {
            $instanceName = $mailAccount.Parent.Parent.DomainInstanceName
        }

        if ($__realCmdlet.ShouldProcess($instanceName, "Updating mail account $($mailAccount.Name)")) {
            $accountChanged = $false

            try {
                if ($__bound.ContainsKey('DisplayName')) { $mailAccount.DisplayName = $DisplayName; $accountChanged = $true }
                if ($__bound.ContainsKey('Description')) { $mailAccount.Description = $Description; $accountChanged = $true }
                if ($__bound.ContainsKey('EmailAddress')) { $mailAccount.EmailAddress = $EmailAddress; $accountChanged = $true }
                if ($__bound.ContainsKey('ReplyToAddress')) { $mailAccount.ReplyToAddress = $ReplyToAddress; $accountChanged = $true }

                if ($accountChanged) {
                    $mailAccount.Alter()
                }
            } catch {
                Stop-Function -Message "Failure updating account properties for $($mailAccount.Name) on $instanceName" -Target $mailAccount -ErrorRecord $_ -Continue -FunctionName Set-DbaDbMailAccount
            }

            try {
                $mailServerObj = $mailAccount.MailServers | Select-Object -First 1

                if ($null -ne $mailServerObj) {
                    if ($__bound.ContainsKey('NewMailServerName')) { $mailServerObj.Rename($NewMailServerName) }
                    if ($__bound.ContainsKey('Port')) { $mailServerObj.Port = $Port }
                    if ($__bound.ContainsKey('EnableSSL')) { $mailServerObj.EnableSsl = $EnableSSL.IsPresent }
                    if ($__bound.ContainsKey('UseDefaultCredentials')) { $mailServerObj.UseDefaultCredentials = $UseDefaultCredentials.IsPresent }
                    if ($__bound.ContainsKey('UserName')) { $mailServerObj.UserName = $UserName }
                    if ($__bound.ContainsKey('Password')) {
                        $mailServerObj.Password = (New-Object System.Net.NetworkCredential("", $Password)).Password
                    }
                    $mailServerObj.Alter()
                }
            } catch {
                Stop-Function -Message "Failure updating mail server for account $($mailAccount.Name) on $instanceName" -Target $mailAccount -ErrorRecord $_ -Continue -FunctionName Set-DbaDbMailAccount
            }

            $mailAccount.Refresh()
            Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name ComputerName -value $mailAccount.Parent.Parent.ComputerName
            Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name InstanceName -value $mailAccount.Parent.Parent.ServiceName
            Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name SqlInstance -value $mailAccount.Parent.Parent.DomainInstanceName
            $mailAccount | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
        }
    }
} $SqlInstance $SqlCredential $Account $InputObject $DisplayName $Description $EmailAddress $ReplyToAddress $NewMailServerName $Port $EnableSSL $UseDefaultCredentials $UserName $Password $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
