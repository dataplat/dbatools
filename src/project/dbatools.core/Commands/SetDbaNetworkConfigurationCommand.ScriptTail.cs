#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaNetworkConfiguration hop script, SECOND half (the apply loop + the sentinel).
/// Substitutions in this half: $Pscmdlet -> $__realCmdlet on the two gates, the
/// Test-ElevationRequirement call routed through the attribution-shim wrapper (declared
/// in the head), and -FunctionName Set-DbaNetworkConfiguration on hop-frame-level
/// Stop-Function/Write-Message (W1-090). The `$output.Exception = ...` Add-Member-less
/// property assignment quirk (adding a property that was never declared on the output
/// object throws, swallowed by the outer catch's Stop-Function -Continue) rides
/// verbatim. See the sibling partial for the split rationale.
/// </summary>
public sealed partial class SetDbaNetworkConfigurationCommand
{
    internal const string ProcessScriptTail = """

    foreach ($netConf in $InputObject) {
        try {
            $output = [PSCustomObject]@{
                ComputerName  = $netConf.ComputerName
                InstanceName  = $netConf.InstanceName
                SqlInstance   = $netConf.SqlInstance
                Changes       = @()
                RestartNeeded = $false
                Restarted     = $false
            }

            if ($__realCmdlet.ShouldProcess("Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                $computerName = Resolve-DbaComputerName -ComputerName $netConf.ComputerName -Credential $Credential
                $null = Set-DbaNetworkConfiguration -__splat @{ ComputerName = $computerName; EnableException = $true }
                $result = Invoke-Command2 -ScriptBlock $wmiScriptBlock -ArgumentList $netConf -ComputerName $computerName -Credential $Credential -ErrorAction Stop
                foreach ($verbose in $result.Verbose) {
                    Write-Message -Level Verbose -Message $verbose -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                }
                $output.Changes = $result.Changes
                if ($result.Exception) {
                    # The new code pattern for WMI calls is used where all exceptions are catched and return as part of an object.
                    $output.Exception = $result.Exception
                    Write-Message -Level Verbose -Message "Execution against $computerName failed with: $($result.Exception)" -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed with: $($result.Exception)" -Target $netConf.ComputerName -ErrorRecord $result.Exception -Continue -FunctionName Set-DbaNetworkConfiguration
                }
            }

            if ($result.Changes.Count -gt 0) {
                $output.RestartNeeded = $true
                if ($RestartService) {
                    if ($__realCmdlet.ShouldProcess("Restarting service for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                        try {
                            $null = Restart-DbaService -ComputerName $netConf.ComputerName -InstanceName $netConf.InstanceName -Credential $Credential -Type Engine -Force -EnableException -Confirm:$false
                            $output.Restarted = $true
                        } catch {
                            Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed ($_). Restart of instance is necessary for the new settings to take effect." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                        }
                    }
                } else {
                    Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) is needed for the changes to take effect." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                }
            }

            $output

        } catch {
            Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) not possible." -Target $netConf.ComputerName -ErrorRecord $_ -Continue -FunctionName Set-DbaNetworkConfiguration
        }
    }
    }

    @{ __w3095State = @{ result = $result } }
} $SqlInstance $Credential $EnableProtocol $DisableProtocol $DynamicPortForIPAll $StaticPortForIPAll $IpAddress $RestartService $InputObject $EnableException $__boundEnableProtocol $__boundDisableProtocol $__boundDynamicPortForIPAll $__boundStaticPortForIPAll $__boundIpAddress $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
