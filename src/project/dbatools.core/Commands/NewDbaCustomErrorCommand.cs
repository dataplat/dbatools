#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates user-defined server messages (custom errors). Port of
/// public/New-DbaCustomError.ps1 (W3-065). The process body rides one VERBATIM module hop
/// per record with $Pscmdlet.ShouldProcess routed to the REAL cmdlet (W1-085 - no
/// ConfirmPreference override in this source, so the Move-family $__realCmdlet convention
/// applies, ConfirmImpact Low mirrored from the explicit source attribute). Bind-time cast
/// parity: [PsIntCast] on BOTH ValidateRange ints (W1-043 - the function converts an
/// explicit null to 0 BEFORE the range check and rejects it with the RANGE message, not the
/// null message) and [PsStringCast] on the ValidateLength MessageText (W1-032 - null
/// converts to "" and PASSES ValidateLength(0,255) exactly like the function). Test-Bound
/// Language/WithLog carried as bound flags; the interpolated syslanguages lookup query and
/// the default-language fallback query ride the hop verbatim (PS-side T-SQL text unchanged
/// per the verbatim-hop convention - the BP-101 SqlParameter hardening applies to real C#
/// ports, not hops). The `.Refresh() does not work as expected` why-comment carries
/// verbatim. Surface pinned by migration/baselines/New-DbaCustomError.json (implicit
/// positions 0-5, ConfirmImpact Low, no aliases).
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaCustomError", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaCustomErrorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The custom message id (50001-2147483647).</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    [ValidateRange(50001, 2147483647)]
    public int MessageID { get; set; }

    /// <summary>The severity level (1-25).</summary>
    [Parameter(Position = 3)]
    [PsIntCast]
    [ValidateRange(1, 25)]
    public int Severity { get; set; }

    /// <summary>The message text (up to 255 characters).</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateLength(0, 255)]
    public string? MessageText { get; set; }

    /// <summary>The message language; defaults to English.</summary>
    [Parameter(Position = 5)]
    public string Language { get; set; } = "English";

    /// <summary>Enables the log mechanism for the message.</summary>
    [Parameter]
    public SwitchParameter WithLog { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Stream one hop PER INSTANCE: a whole-array hop batches every instance's live
        // Debug/Verbose ahead of all buffered output, where the source's foreach
        // interleaves them per instance (W2-010 P2A; coordinator 25a09f3 ruling). The
        // source loop body has no cross-instance state.
        foreach (DbaInstanceParameter instance in SqlInstance)
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
            new[] { instance }, SqlCredential, MessageID, Severity, MessageText ?? "", Language,
                WithLog.ToBool(), EnableException.ToBool(),
                TestBound(nameof(Language)), TestBound(nameof(WithLog)), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the process body VERBATIM per record. Substitutions only: Test-Bound Language/
    // WithLog -> carried bound flags, $Pscmdlet -> $__realCmdlet, and explicit
    // -FunctionName New-DbaCustomError on Stop-Function/Write-Message (W1-090). The
    // syslanguages queries keep their source-interpolated T-SQL text (verbatim-hop
    // convention) and the .Refresh() why-comment carries as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $MessageID, $Severity, $MessageText, $Language, $WithLog, $EnableException, $__boundLanguage, $__boundWithLog, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [int32]$MessageID, [int32]$Severity, [String]$MessageText, [String]$Language, $WithLog, $EnableException, $__boundLanguage, $__boundWithLog, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaCustomError
        }

        $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

        if ($__boundLanguage) {
            if ($null -eq $languageDetails) {
                Stop-Function -Message "$instance does not have the $Language installed" -Target $instance -Continue -FunctionName New-DbaCustomError
            }
        }

        $languageName = $languageDetails.name
        $languageAlias = $languageDetails.alias
        $langId = $languageDetails.msglangid

        if ($__realCmdlet.ShouldProcess($instance, "Creating new server message with id $MessageID on $instance")) {
            Write-Message -Level Verbose -Message "Creating new server message with id $MessageID on $instance" -FunctionName New-DbaCustomError -ModuleName "dbatools"
            try {
                $userDefinedMessage = New-Object -TypeName Microsoft.SqlServer.Management.Smo.UserDefinedMessage
                $userDefinedMessage.Parent = $server
                $userDefinedMessage.ID = $MessageID

                if ($__boundLanguage) {
                    $userDefinedMessage.Language = $Language
                } else {
                    $userDefinedMessage.Language = ($server.Query("SELECT syslang.name FROM sys.syslanguages syslang JOIN sys.configurations config ON syslang.langid = config.value_in_use AND config.name = 'default language'")).name
                }

                $userDefinedMessage.Severity = $Severity
                $userDefinedMessage.Text = $MessageText

                if ($__boundWithLog) {
                    $userDefinedMessage.IsLogged = $true
                }

                $userDefinedMessage.Create()

                # return the new message object from the server to get all properties refreshed (the $userDefinedMessage.Refresh() method does not work as expected)
                $server.UserDefinedMessages | Where-Object { $_.ID -eq $MessageID -and $_.Language -eq $userDefinedMessage.Language }
            } catch {
                Stop-Function -Message "Error occurred while trying to create a message with id $MessageID on $instance" -ErrorRecord $_ -Continue -FunctionName New-DbaCustomError
            }
        }
    }
} $SqlInstance $SqlCredential $MessageID $Severity $MessageText $Language $WithLog $EnableException $__boundLanguage $__boundWithLog $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
