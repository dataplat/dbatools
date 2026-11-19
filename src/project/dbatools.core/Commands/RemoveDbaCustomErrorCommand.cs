#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes user-defined server messages (custom errors). Port of
/// public/Remove-DbaCustomError.ps1 (W3-073), sibling of New-DbaCustomError (W3-065) with
/// the same shape: the process body rides one VERBATIM module hop per record with
/// $Pscmdlet.ShouldProcess routed to the REAL cmdlet (W1-085, ConfirmImpact Low mirrored
/// from the explicit source attribute). Bind-time cast parity: [PsIntCast] on the
/// ValidateRange MessageID (W1-043 - the function converts an explicit null to 0 BEFORE
/// the range check and rejects it with the RANGE message, not the null message).
/// Test-Bound Language carried as a bound flag; the interpolated syslanguages lookup and
/// the sp_dropmessage calls ride the hop verbatim (PS-side T-SQL text unchanged per the
/// verbatim-hop convention - BP-101 SqlParameter hardening applies to real C# ports, not
/// hops), including the source's us_english drop-order logic and its why-comments.
/// NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaCustomError.json (implicit positions 0-3, ConfirmImpact
/// Low, SqlInstance Mandatory pos0 VFP).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaCustomError", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class RemoveDbaCustomErrorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The custom message id to remove (50001-2147483647).</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    [ValidateRange(50001, 2147483647)]
    public int MessageID { get; set; }

    /// <summary>The language version to remove; "All" removes every version. Defaults to English.</summary>
    [Parameter(Position = 3)]
    public string Language { get; set; } = "English";

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
            new[] { instance }, SqlCredential, MessageID, Language, EnableException.ToBool(),
                TestBound(nameof(Language)), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the process body VERBATIM per record. Substitutions only: Test-Bound Language ->
    // the carried $__boundLanguage flag, $Pscmdlet -> $__realCmdlet, and explicit
    // -FunctionName Remove-DbaCustomError on Stop-Function/Write-Message (W1-090). The
    // syslanguages lookup, the sp_dropmessage calls, the us_english drop-order logic and
    // every why-comment ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $MessageID, $Language, $EnableException, $__boundLanguage, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [int32]$MessageID, [String]$Language, $EnableException, $__boundLanguage, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaCustomError
        }

        if ($Language -ine "All") {
            $languageDetails = $server.Query("SELECT TOP 1 name, alias, msglangid FROM sys.syslanguages WHERE name = '$Language' OR alias = '$Language'")

            if ($__boundLanguage -and $null -eq $languageDetails) {
                Stop-Function -Message "$instance does not have the $Language installed" -Target $instance -Continue -FunctionName Remove-DbaCustomError
            }

            $languageName = $languageDetails.name
            $languageAlias = $languageDetails.alias
            $langId = $languageDetails.msglangid
        }

        if ($__realCmdlet.ShouldProcess($instance, "Removing server message with id $MessageID from $instance")) {
            Write-Message -Level Verbose -Message "Removing server message with id $MessageID and language $Language from $instance" -FunctionName Remove-DbaCustomError -ModuleName "dbatools"

            # Use sp_dropmessage directly - more reliable than SMO Drop() method
            # sp_dropmessage handles the proper drop order automatically
            try {
                if ($Language -ieq "All") {
                    $server.Query("EXEC sp_dropmessage @msgnum = $MessageID, @lang = 'all'")
                } else {
                    # Check if this is English and other language versions exist
                    # SQL Server requires all localized versions to be dropped before us_english
                    # If dropping English, we must drop all versions
                    if ($languageName -eq "us_english") {
                        $otherLanguages = $server.Query("SELECT COUNT(*) AS cnt FROM sys.messages WHERE message_id = $MessageID AND language_id <> 1033")
                        if ($otherLanguages.cnt -gt 0) {
                            # Other languages exist, must drop all
                            $server.Query("EXEC sp_dropmessage @msgnum = $MessageID, @lang = 'all'")
                        } else {
                            # Only English exists, drop just English
                            $server.Query("EXEC sp_dropmessage @msgnum = $MessageID, @lang = '$languageName'")
                        }
                    } else {
                        # Non-English language, drop just that language
                        $server.Query("EXEC sp_dropmessage @msgnum = $MessageID, @lang = '$languageName'")
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while trying to remove message $MessageID from $instance" -ErrorRecord $_ -Continue -FunctionName Remove-DbaCustomError
            }

            # Refresh the UserDefinedMessages collection to reflect the changes
            $server.UserDefinedMessages.Refresh()
        }
    }
} $SqlInstance $SqlCredential $MessageID $Language $EnableException $__boundLanguage $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
