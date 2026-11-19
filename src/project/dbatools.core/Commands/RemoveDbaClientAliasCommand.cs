#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server client aliases from the Windows registry (HKLM ConnectTo keys, both
/// 32-bit and 64-bit hives). Port of public/Remove-DbaClientAlias.ps1 (W1-033). Sibling of
/// New-DbaClientAlias (W1-026): the registry scriptblock rides Invoke-Command2 VERBATIM
/// (local in-process or remoting, exactly like the function) and Test-ElevationRequirement
/// runs module-scoped with -Continue, so the private helper's dynamically scoped continue
/// propagates out of the nested script as the engine flow-control exception and continues
/// THIS cmdlet's computer loop. Warnings from both helpers merge back 3&gt;&amp;1 and re-emit
/// through this cmdlet's warning stream (display parity; NOTE lab-proven both editions:
/// caller -WarningVariable captures ZERO from the Invoke-Command2 hop for the function and
/// the cmdlet alike - 3&gt;&amp;1 at the caller is the observing shape). The hops receive the
/// RAW DbaInstanceParameter element (null included) like the function's $computer, and the
/// ShouldProcess target interpolates it PS-style (FullSmoName, empty for null). The hop
/// script returns a terminating failure as marker data so output streamed before the
/// failure still reaches the pipeline (function stream parity). PS function parameters are
/// positional by default, so Positions 0-2 are pinned. One object per removed alias is
/// emitted immediately to the pipeline.
/// Surface pinned by migration/baselines/Remove-DbaClientAlias.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaClientAlias", SupportsShouldProcess = true)]
public sealed class RemoveDbaClientAliasCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 2)]
    [Alias("AliasName")]
    public string[] Alias { get; set; } = null!;

    protected override void BeginProcessing()
    {
        // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME (bind-time cast;
        // a null environment value casts to null and the process loop just never runs).
        if (!TestBound("ComputerName"))
        {
            string? localName = Environment.GetEnvironmentVariable("COMPUTERNAME");
            if (localName is not null)
                ComputerName = (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(localName, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
    }

    protected override void ProcessRecord()
    {
        if (ComputerName is null)
            return;

        // PS: foreach ($computer in $ComputerName) - member enumeration of the parameter array.
        // Elements can be null (PS never dereferences $computer; the hops and the message
        // interpolation receive it as-is - lab-proven: the function surfaces the nested
        // binding error and continues to the next computer).
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            // PS interpolation "$computer": null renders empty; a DbaInstanceParameter renders
            // its ToString (FullSmoName) - lab-proven WhatIf target "x on WORKSTATION\someinstance"
            // for instance-shaped input, NOT the bare ComputerName.
            string computerDisplay = computer is null ? "" : PSObject.AsPSObject(computer).ToString();

            // PS: $null = Test-ElevationRequirement -ComputerName $computer -Continue -
            // output discarded, warnings bubble, the failure continue targets this loop. The
            // hop receives the RAW element exactly like the function passed $computer.
            try
            {
                NestedCommand.InvokeScoped(this, TestElevationScript, computer, EnableException.ToBool());
            }
            catch (FlowControlException)
            {
                continue;
            }

            // PS: if ($PSCmdlet.ShouldProcess("$($Alias -join ', ') on $computer", "Remove aliases"))
            if (ShouldProcess(string.Join(", ", Alias) + " on " + computerDisplay, "Remove aliases"))
            {
                bool hopFailed = false;
                try
                {
                    foreach (PSObject item in NestedCommand.InvokeScoped(this, InvokeCommand2Script, computer, Credential, Alias))
                    {
                        // The hop script catches a terminating failure and returns the caught
                        // record AS DATA after the output already streamed, so objects the
                        // registry scriptblock emitted BEFORE the failure still reach the
                        // pipeline exactly like the function's direct Invoke-Command2 call
                        // (lab-proven: the 32-bit hive's Removed object precedes an invalid-
                        // wildcard failure; buffering in the hop used to discard it).
                        ErrorRecord? caught = ExtractCaughtError(item);
                        if (caught is not null)
                        {
                            // PS: catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue }
                            StopFunction("Failure", target: computer, errorRecord: caught, continueLoop: true);
                            hopFailed = true;
                            break;
                        }
                        WriteObject(item);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue }
                    StopFunction("Failure", target: computer, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                    continue;
                }
                if (hopFailed)
                    continue;
            }
        }
    }

    /// <summary>Detects the hop script's caught-error marker (the script-side catch returns
    /// the ErrorRecord as data so pre-failure output survives - the W1-019 outcome-as-data
    /// wrapper shape) and unwraps the record.</summary>
    private static ErrorRecord? ExtractCaughtError(PSObject? item)
    {
        if (item?.BaseObject is PSCustomObject)
        {
            PSPropertyInfo? marker = item.Properties["__dbatoolsCaughtError"];
            if (marker?.Value is not null)
                return PsAssignment.Unwrap(marker.Value) as ErrorRecord;
        }
        return null;
    }

    /// <summary>PS: catch { $_ } - a nested terminating error carries the original failing
    /// record; a hand-built RuntimeException's lazy record drops the inner chain
    /// (ParentContainsErrorRecordException), so that shape rebuilds from the exception.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Remove-DbaClientAlias", ErrorCategory.NotSpecified, null);
    }

    private const string TestElevationScript = """
param($computer, $enable)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $enable)
    Test-ElevationRequirement -ComputerName $computer -Continue -EnableException $enable 3>&1
} $computer $enable
""";

    // The inner registry scriptblock is VERBATIM from the function's begin block (comments
    // included) - Invoke-Command2 runs it in-process locally or serializes it for remoting.
    private const string InvokeCommand2Script = """
param($computer, $credential, $Alias)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $credential, $Alias)
    $scriptBlock = {
        $Alias = $args

        $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"

        foreach ($basekey in $basekeys) {
            $fullKey = "$basekey\Client\ConnectTo"
            if ((Test-Path $fullKey) -eq $false) {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Warning "Registry key ($fullKey) does not exist on $env:COMPUTERNAME"
                continue
            }

            if ($basekey -like "*WOW64*") {
                $architecture = "32-bit"
            } else {
                $architecture = "64-bit"
            }

            $all = Get-Item -Path $fullKey
            foreach ($entry in $all) {
                $e = $entry.ToString().Replace('HKEY_LOCAL_MACHINE', 'HKLM:\')
                foreach ($a in $Alias) {
                    if ($entry.Property -contains $a) {
                        $null = Remove-ItemProperty -Path $e -Name $a
                        [PSCustomObject]@{
                            ComputerName = $env:COMPUTERNAME
                            Architecture = $architecture
                            Alias        = $a
                            Status       = "Removed"
                        }
                    }
                }
            }
        }
    }
    try {
        Invoke-Command2 -ComputerName $computer -Credential $credential -ScriptBlock $scriptBlock -ErrorAction Stop -Verbose:$false -ArgumentList $Alias 3>&1
    } catch {
        # outcome-as-data: pre-failure output already streamed; the caught record rides back
        # as a marker object the cmdlet routes to Stop-Function (never a real output shape)
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $computer $credential $Alias
""";
}
