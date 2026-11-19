#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a new Database Mail account.
/// </summary>
/// <remarks>
/// The credential-argument validation, the instance connection, the optional mail-server existence check,
/// the SMO account construction, the mail-server configuration, the Alter/Create, and the result-object
/// shaping all run the original dbatools PowerShell body inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// Process-only, single per-record hop, NO cross-record state: SqlInstance is the only pipeline-bound
/// parameter and $accountObj is created and emitted entirely within the ShouldProcess block of one instance
/// iteration (a declined ShouldProcess creates/emits nothing), so nothing leaks across records. The two
/// top validations use no-Continue Stop-Functions that set the function-scope interrupt and return, but
/// nothing reads Test-FunctionInterrupt (inert); the return exits the hop, and under -EnableException the
/// Stop-Function throws (re-thrown, terminating).
///
/// The many Test-Bound sites are replaced by lookups on this cmdlet's own MyInvocation.BoundParameters
/// (passed as $__bound), because Test-Bound reads the CALLER's $PSBoundParameters and inside the hop the
/// caller is the inner scriptblock (all params look bound). Single-name -> $__bound.ContainsKey; the two
/// multi-name sites map by their Min/Max: "UserName, Password" (default Min=1) -> an -or, and
/// "UserName, Password -Min 1 -Max 1" (exactly one) -> an -xor. -Force is consumed ONLY via Test-Bound
/// (it bypasses the mail-server validation; it is NOT a confirm suppressor here), so it is passed only
/// through $__bound, never as a value. EnableSSL/UseDefaultCredentials are passed as their SwitchParameter
/// values so the body's .IsPresent resolves. The source's "[string]$DisplayName = $Account" parameter
/// default (a cross-parameter default the compiled attribute cannot express) is reproduced by a seed at the
/// top of the hop.
///
/// Output streams: each created account is emitted before a later instance may fail under -EnableException
/// (DEF-001). This cmdlet supplies the real ShouldProcess runtime (ConfirmImpact Low, no -Force gate).
/// Surface pinned by migration/baselines/New-DbaDbMailAccount.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbMailAccount", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbMailAccountCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The unique name for the Database Mail account being created.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [Alias("Name")]
    [PsStringCast]
    public string Account { get; set; } = null!;

    /// <summary>The friendly name that appears in the 'From' field of outgoing emails (defaults to Account).</summary>
    [Parameter(Position = 3)]
    public string? DisplayName { get; set; }

    /// <summary>Optional documentation text describing the account's purpose.</summary>
    [Parameter(Position = 4)]
    public string? Description { get; set; }

    /// <summary>The sender email address for outgoing messages.</summary>
    [Parameter(Mandatory = true, Position = 5)]
    [PsStringCast]
    public string EmailAddress { get; set; } = null!;

    /// <summary>An alternate reply-to email address.</summary>
    [Parameter(Position = 6)]
    public string? ReplyToAddress { get; set; }

    /// <summary>The SMTP server hostname or IP address to use for this account.</summary>
    [Parameter(Position = 7)]
    public string? MailServer { get; set; }

    /// <summary>The TCP port used to connect to the SMTP server.</summary>
    [Parameter(Position = 8)]
    [ValidateRange(1, 65535)]
    public int Port { get; set; }

    /// <summary>Enables SSL/TLS encryption for the SMTP connection.</summary>
    [Parameter]
    public SwitchParameter EnableSSL { get; set; }

    /// <summary>Use Windows integrated security for SMTP authentication.</summary>
    [Parameter]
    public SwitchParameter UseDefaultCredentials { get; set; }

    /// <summary>The username for SMTP authentication.</summary>
    [Parameter(Position = 9)]
    public string? UserName { get; set; }

    /// <summary>The password for SMTP authentication as a SecureString.</summary>
    [Parameter(Position = 10)]
    public SecureString? Password { get; set; }

    /// <summary>Bypass the mail-server existence validation.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Reproduce Test-Bound faithfully: this cmdlet's own bound parameters (this is also how -Force and
        // the DisplayName default are resolved inside the hop).
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
            SqlInstance, SqlCredential, Account, DisplayName, Description, EmailAddress, ReplyToAddress,
            MailServer, Port, EnableSSL, UseDefaultCredentials, UserName, Password,
            EnableException.ToBool(), bound, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, the
    // Test-Bound sites -> $__bound.ContainsKey lookups (single name; the UserName/Password default-Min site
    // -> -or; the -Min 1 -Max 1 site -> -xor), and -FunctionName New-DbaDbMailAccount on the direct
    // Stop-Function sites. The source's "[string]$DisplayName = $Account" param default is reproduced by the
    // seed at the top (applied at bind-time in the source, before the body runs).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Account, $DisplayName, $Description, $EmailAddress, $ReplyToAddress, $MailServer, $Port, $EnableSSL, $UseDefaultCredentials, $UserName, $Password, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Account, [string]$DisplayName, [string]$Description, [string]$EmailAddress, [string]$ReplyToAddress, [string]$MailServer, [int]$Port, $EnableSSL, $UseDefaultCredentials, [string]$UserName, [System.Security.SecureString]$Password, $EnableException, $__bound, $__realCmdlet)
    # Reproduce the source param default "[string]$DisplayName = $Account" (bind-time in the source).
    if (-not $__bound.ContainsKey('DisplayName')) { $DisplayName = $Account }

    if ($UseDefaultCredentials.IsPresent -and ($__bound.ContainsKey('UserName') -or $__bound.ContainsKey('Password'))) {
        Stop-Function -Category InvalidArgument -Message "You cannot specify -UseDefaultCredentials with -UserName or -Password." -FunctionName New-DbaDbMailAccount
        return
    }

    if ($__bound.ContainsKey('UserName') -xor $__bound.ContainsKey('Password')) {
        Stop-Function -Category InvalidArgument -Message "You must specify both -UserName and -Password together." -FunctionName New-DbaDbMailAccount
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDbMailAccount
        }

        if ($__bound.ContainsKey('MailServer')) {
            if (-not (Get-DbaDbMailServer -SqlInstance $server -Server $MailServer) -and -not ($__bound.ContainsKey('Force'))) {
                Stop-Function -Message "The mail server '$MailServer' does not exist on $instance. Use -Force if you need to create it anyway." -Target $instance -Continue -FunctionName New-DbaDbMailAccount
            }
        }

        if ($__realCmdlet.ShouldProcess($instance, "Creating new db mail account called $Account")) {
            try {
                $accountObj = New-Object Microsoft.SqlServer.Management.SMO.Mail.MailAccount $server.Mail, $Account
                $accountObj.DisplayName = $DisplayName
                $accountObj.Description = $Description
                $accountObj.EmailAddress = $EmailAddress
                $accountObj.ReplyToAddress = $ReplyToAddress
                $accountObj.Create()
            } catch {
                Stop-Function -Message "Failure creating db mail account" -Target $Account -ErrorRecord $_ -Continue -FunctionName New-DbaDbMailAccount
            }

            try {
                if ($__bound.ContainsKey('MailServer')) {
                    $mailServerObj = $accountObj.MailServers.Item($server.DomainInstanceName)
                    $mailServerObj.Rename($MailServer)
                } else {
                    $mailServerObj = $accountObj.MailServers | Select-Object -First 1
                }

                if ($null -ne $mailServerObj) {
                    if ($__bound.ContainsKey('Port')) { $mailServerObj.Port = $Port }
                    if ($__bound.ContainsKey('EnableSSL')) { $mailServerObj.EnableSsl = $EnableSSL.IsPresent }
                    if ($__bound.ContainsKey('UseDefaultCredentials')) { $mailServerObj.UseDefaultCredentials = $UseDefaultCredentials.IsPresent }
                    if ($__bound.ContainsKey('UserName')) { $mailServerObj.UserName = $UserName }
                    if ($__bound.ContainsKey('Password')) {
                        $mailServerObj.Password = (New-Object System.Net.NetworkCredential("", $Password)).Password
                    }
                    $mailServerObj.Alter()
                }

                $accountObj.Refresh()
                Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                $accountObj | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
            } catch {
                Stop-Function -Message "Failure returning output" -ErrorRecord $_ -Continue -FunctionName New-DbaDbMailAccount
            }
        }
    }
} $SqlInstance $SqlCredential $Account $DisplayName $Description $EmailAddress $ReplyToAddress $MailServer $Port $EnableSSL $UseDefaultCredentials $UserName $Password $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
