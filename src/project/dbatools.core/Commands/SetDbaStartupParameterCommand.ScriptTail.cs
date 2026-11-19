#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaStartupParameter process hop script, SECOND half (the WMI apply scriptblock +
/// the gated Invoke-ManagedComputerCommand/output region). The gate stays on the INNER
/// $PSCmdlet (Force convention; single record - no transplant). The $wmi variable
/// inside the remote scriptblock is provided by Invoke-ManagedComputerCommand's remote
/// context and rides verbatim. See the sibling partial for the split rationale.
/// </summary>
public sealed partial class SetDbaStartupParameterCommand
{
    internal const string ProcessScriptTail = """

            $instanceName = $instance.InstanceName
            $displayName = "SQL Server ($instanceName)"

            $scriptBlock = {
                #Variable marked as unused by PSScriptAnalyzer
                #$instance = $args[0]
                $displayName = $args[1]
                $parameterString = $args[2]

                $wmiSvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayName }
                $wmiSvc.StartupParameters = $parameterString
                $wmiSvc.Alter()
                $wmiSvc.Refresh()
                if ($wmiSvc.StartupParameters -eq $parameterString) {
                    $true
                } else {
                    $false
                }
            }
            if ($PSCmdlet.ShouldProcess("Setting startup parameters on $instance to $parameterString")) {
                try {
                    if ($Credential) {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -Credential $Credential -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                    } else {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -scriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name Notes -Value "Startup parameters changed on $instance. You must restart SQL Server for changes to take effect."
                    }
                    $output
                } catch {
                    Stop-Function -Message "Startup parameter update failed on $instance. " -Target $instance -ErrorRecord $_ -FunctionName Set-DbaStartupParameter
                    return
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Credential $MasterData $MasterLog $ErrorLog $TraceFlag $CommandPromptStart $MinimalStart $MemoryToReserve $SingleUser $SingleUserDetails $NoLoggingToWinEvents $StartAsNamedInstance $DisableMonitoring $IncreasedExtents $TraceFlagOverride $StartupConfig $Offline $Force $EnableException $__boundParams $__hopInterrupted $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
