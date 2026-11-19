#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server client aliases from the Windows registry on local or remote computers.
/// Port of public/Get-DbaClientAlias.ps1; the registry-reading scriptblock runs verbatim
/// through RemoteExecutionService (Invoke-Command2 semantics: in-process for the local
/// computer, cached PSSession for remote ones), so registry provider behavior, PSCustomObject
/// shaping and error semantics ride the real engine. Surface pinned by
/// migration/baselines/Get-DbaClientAlias.json (single set, ComputerName pipeline pos0).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaClientAlias")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaClientAliasCommand : DbaBaseCmdlet
{
    /// <summary>The computer(s) to retrieve SQL Server client aliases from; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternative credentials for the remote connection.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 scriptblock (cooked, no -Raw), verbatim from the PS source.
    private const string AliasScript = @"
            function Get-ItemPropertyValue {
                param (
                    [parameter()]
                    [String]$Path,
                    [parameter()]
                    [String]$Name
                )
                (Get-ItemProperty -LiteralPath $Path -Name $Name).$Name
            }

            $basekeys = ""HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer"", ""HKLM:\SOFTWARE\Microsoft\MSSQLServer""

            foreach ($basekey in $basekeys) {

                <# DO NOT use Write-Message as this is inside of a scriptblock #>
                if ((Test-Path $basekey) -eq $false) {
                    continue
                }

                $client = ""$basekey\Client""

                if ((Test-Path $client) -eq $false) {
                    continue
                }

                $connect = ""$client\ConnectTo""

                if ((Test-Path $connect) -eq $false) {
                    continue
                }

                if ($basekey -like ""*WOW64*"") {
                    $architecture = ""32-bit""
                } else {
                    $architecture = ""64-bit""
                }

                # ""Get SQL Server alias for $ComputerName for $architecture""
                $all = Get-Item -Path $connect
                foreach ($entry in $all.Property) {
                    $value = Get-ItemPropertyValue -Path $connect -Name $entry
                    $clean = $value.Replace('DBNMPNTW,', '').Replace('DBMSSOCN,', '')
                    if ($value.StartsWith('DBMSSOCN')) { $protocol = 'TCP/IP' } else { $protocol = 'Named Pipes' }
                    [PSCustomObject]@{
                        ComputerName   = $env:COMPUTERNAME
                        NetworkLibrary = $protocol
                        ServerName     = $clean
                        AliasName      = $entry
                        AliasString    = $value
                        Architecture   = $architecture
                    }
                }
            }
        ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            try
            {
                if (computer is null)
                {
                    // PS: an explicit null element binds to Invoke-Command2's class-typed
                    // [DbaInstanceParameter] parameter, walks the remote branch and dies at
                    // New-PSSession's ComputerName ValidateNotNullOrEmpty under -ErrorAction
                    // Stop. Reproduce the exact failing engine statement so the catch
                    // composes the same "Failure | The argument is null or empty..." record
                    // (lab-proven both editions).
                    Hashtable splatSession = new();
                    splatSession["ComputerName"] = null;
                    splatSession["ErrorAction"] = "Stop";
                    try
                    {
                        NestedCommand.Invoke(this, "New-PSSession", splatSession);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        // ParameterBindingException.ErrorRecord flattens to a
                        // ParentContainsErrorRecordException (composite message, no inner
                        // chain); rebuild the record around the REAL exception so the
                        // deepest-first message walk lands on the inner
                        // ValidationMetadataException text exactly like the function's catch.
                        string errorId = rex.ErrorRecord is null ? "dbatools_Get-DbaClientAlias" : rex.ErrorRecord.FullyQualifiedErrorId;
                        ErrorCategory category = rex.ErrorRecord is null ? ErrorCategory.NotSpecified : rex.ErrorRecord.CategoryInfo.Category;
                        StopFunction("Failure", target: computer, errorRecord: new ErrorRecord(rex, errorId, category, computer), continueLoop: true);
                    }
                    continue;
                }

                RemoteExecutionService.RemoteCommandRequest request = new()
                {
                    ComputerName = computer,
                    Credential = Credential,
                    ScriptText = AliasScript
                };
                RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);

                // PS: -ErrorAction Stop on the Invoke-Command2 call - a populated error bag
                // maps to the catch's Stop-Function, like W5-011.
                if (result.Errors.Count > 0)
                {
                    StopFunction("Failure", target: computer, errorRecord: result.Errors[0], continueLoop: true);
                    continue;
                }

                foreach (PSObject item in result.Output)
                {
                    WriteObject(item);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction("Failure", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: computer, exception: ex, continueLoop: true);
                continue;
            }
        }
    }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
