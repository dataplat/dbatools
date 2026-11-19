#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo.Mail;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves and decorates Database Mail accounts. The SqlMail aggregation, SMO traversal,
/// filtering, relationship lookup, and output shaping remain a module-scoped PowerShell
/// compatibility hop. Surface pinned by migration/baselines/Get-DbaDbMailAccount.json.
/// </summary>
/// <remarks>
/// Output streams as produced. A single record can hold several accounts (a directly bound
/// InputObject array, or the accounts gathered across a multi-instance -SqlInstance), and an early
/// one is emitted before a later one may throw under -EnableException; the script streamed those
/// early results, so buffering and losing them to a later terminating failure would diverge.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaDbMailAccount")]
public sealed class GetDbaDbMailAccountCommand : DbaBaseCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Database Mail account names to include.</summary>
    [Parameter(Position = 2)]
    public string[]? Account { get; set; }

    /// <summary>Database Mail account names to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeAccount { get; set; }

    /// <summary>SqlMail objects supplied directly or through the pipeline.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    [PsDbMailArrayCast]
    public SqlMail[]? InputObject { get; set; }

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
        }, BodyScript,
            SqlInstance, SqlCredential, Account, ExcludeAccount, InputObject,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Account, $ExcludeAccount, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential,
        [string[]]$Account, [string[]]$ExcludeAccount,
        [Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]]$InputObject, $EnableException)

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDbMail -SqlInstance $instance -SqlCredential $SqlCredential
    }

    if (-not $InputObject) {
        Stop-Function -Message "No servers to process" -FunctionName Get-DbaDbMailAccount
        return
    }

    foreach ($mailserver in $InputObject) {
        try {
            $accounts = $mailserver.Accounts

            if ($Account) {
                $accounts = $accounts | Where-Object Name -in $Account
            }

            if ($ExcludeAccount) {
                $accounts = $accounts | Where-Object Name -notin $ExcludeAccount
            }

            foreach ($acct in $accounts) {
                $acct | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                $acct | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                $acct | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance
                $acct | Add-Member -Force -MemberType NoteProperty -Name MailProfile -value $acct.GetAccountProfileNames()
                $acct | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers, MailProfile
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Get-DbaDbMailAccount
        }
    }
} $SqlInstance $SqlCredential $Account $ExcludeAccount $InputObject $EnableException @__commonParameters 3>&1 2>&1
""";
}

/// <summary>Reproduces the advanced function's typed SqlMail array conversion.</summary>
internal sealed class PsDbMailArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;

        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(SqlMail[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}
