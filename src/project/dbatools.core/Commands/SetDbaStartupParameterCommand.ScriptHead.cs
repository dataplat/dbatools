#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaStartupParameter process hop script, FIRST half (through the trace-flag
/// section). The verbatim process body exceeds the 400-line file maximum in one file,
/// so the script is split at a section boundary into two compile-time-concatenated
/// constants (the W3-081 pattern) - the joined text is byte-identical to the
/// single-constant form (see SetDbaStartupParameterCommand.cs). Substitutions in this
/// half: the Force/ConfirmPreference line at hop top (gate lives on the INNER $PSCmdlet
/// per the W3-005/W3-064 convention - single record, no transplant), $__hopInterrupted
/// ahead of the verbatim Test-FunctionInterrupt gate, $PSBoundParameters ->
/// $__boundParams (dictionary carry), and -FunctionName Set-DbaStartupParameter on
/// hop-frame Stop-Function/Write-Message (W1-090).
/// </summary>
public sealed partial class SetDbaStartupParameterCommand
{
    internal const string ProcessScriptHead = """"
param($SqlInstance, $SqlCredential, $Credential, $MasterData, $MasterLog, $ErrorLog, $TraceFlag, $CommandPromptStart, $MinimalStart, $MemoryToReserve, $SingleUser, $SingleUserDetails, $NoLoggingToWinEvents, $StartAsNamedInstance, $DisableMonitoring, $IncreasedExtents, $TraceFlagOverride, $StartupConfig, $Offline, $Force, $EnableException, $__boundParams, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, [string]$MasterData, [string]$MasterLog, [string]$ErrorLog, [string[]]$TraceFlag, $CommandPromptStart, $MinimalStart, [int]$MemoryToReserve, $SingleUser, [string]$SingleUserDetails, $NoLoggingToWinEvents, $StartAsNamedInstance, $DisableMonitoring, $IncreasedExtents, $TraceFlagOverride, [object]$StartupConfig, $Offline, $Force, $EnableException, $__boundParams, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    . {
        if ($__hopInterrupted) { return }
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if (-not $Offline) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Write-Message -Level Warning -Message "Failed to connect to $instance, will try to work with just WMI. Path options will be ignored unless Force was indicated" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                    $server = $instance
                    $Offline = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Offline switch set, proceeding with just WMI" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                $server = $instance
            }

            # Get Current parameters (uses WMI) -- requires elevated session
            try {
                $currentStartup = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Unable to gather current startup parameters" -Target $instance -ErrorRecord $_ -FunctionName Set-DbaStartupParameter
                return
            }
            $originalParamString = $currentStartup.ParameterString
            $parameterString = $null

            Write-Message -Level Verbose -Message "Original startup parameter string: $originalParamString" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"

            if ('StartupConfig' -in $__boundParams.Keys) {
                Write-Message -Level VeryVerbose -Message "startupObject passed in" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                $newStartup = $StartupConfig
                $TraceFlagOverride = $true
            } else {
                Write-Message -Level VeryVerbose -Message "Parameters passed in" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                $newStartup = $currentStartup.PSObject.Copy()
                foreach ($param in ($__boundParams.Keys | Where-Object { $_ -in ($newStartup.PSObject.Properties.Name) })) {
                    if ($__boundParams.Item($param) -ne $newStartup.$param) {
                        $newStartup.$param = $__boundParams.Item($param)
                    }
                }
            }

            if (!($currentStartup.SingleUser)) {

                if ($newStartup.MasterData.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterData path" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                        $parameterString += "-d$($currentStartup.MasterData);"

                    } else {
                        if ($Force) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterData -Parent)) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterData file is not reachable by instance $instance" -FunctionName Set-DbaStartupParameter
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterData value must be provided" -FunctionName Set-DbaStartupParameter
                    return
                }

                if ($newStartup.ErrorLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested ErrorLog path" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                        $parameterString += "-e$($currentStartup.ErrorLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.ErrorLog -Parent)) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } else {
                            Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $instance" -FunctionName Set-DbaStartupParameter
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "ErrorLog value must be provided" -FunctionName Set-DbaStartupParameter
                    return
                }

                if ($newStartup.MasterLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterLog path" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                        $parameterString += "-l$($currentStartup.MasterLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterLog -Parent)) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterLog  file is not reachable by $instance" -FunctionName Set-DbaStartupParameter
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterLog value must be provided." -FunctionName Set-DbaStartupParameter
                    return
                }
            } else {

                Write-Message -Level Verbose -Message "Instance is presently configured for single user, skipping path validation" -FunctionName Set-DbaStartupParameter -ModuleName "dbatools"
                if ($newStartup.MasterData.Length -gt 0) {
                    $parameterString += "-d$($newStartup.MasterData);"
                } else {
                    Stop-Function -Message "Must have a value for MasterData" -FunctionName Set-DbaStartupParameter
                    return
                }
                if ($newStartup.ErrorLog.Length -gt 0) {
                    $parameterString += "-e$($newStartup.ErrorLog);"
                } else {
                    Stop-Function -Message "Must have a value for Errorlog" -FunctionName Set-DbaStartupParameter
                    return
                }
                if ($newStartup.MasterLog.Length -gt 0) {
                    $parameterString += "-l$($newStartup.MasterLog);"
                } else {
                    Stop-Function -Message "Must have a value for MasterLog" -FunctionName Set-DbaStartupParameter
                    return
                }
            }

            if ($newStartup.CommandPromptStart) {
                $parameterString += "-c;"
            }
            if ($newStartup.MinimalStart) {
                $parameterString += "-f;"
            }
            if ($newStartup.MemoryToReserve -notin ($null, 0)) {
                $parameterString += "-g$($newStartup.MemoryToReserve)"
            }
            if ($newStartup.SingleUser) {
                if ($SingleUserDetails.Length -gt 0) {
                    if ($SingleUserDetails -match ' ') {
                        $SingleUserDetails = """$SingleUserDetails"""
                    }
                    $parameterString += "-m$SingleUserDetails;"
                } else {
                    $parameterString += "-m;"
                }
            }
            if ($newStartup.NoLoggingToWinEvents) {
                $parameterString += "-n;"
            }
            If ($newStartup.StartAsNamedInstance) {
                $parameterString += "-s;"
            }
            if ($newStartup.DisableMonitoring) {
                $parameterString += "-x;"
            }
            if ($newStartup.IncreasedExtents) {
                $parameterString += "-E;"
            }
            if ($newStartup.TraceFlags -eq 'None') {
                $newStartup.TraceFlags = ''
            }
            if ($TraceFlagOverride -and 'TraceFlag' -in $__boundParams.Keys) {
                if ($null -ne $TraceFlag -and '' -ne $TraceFlag) {
                    $newStartup.TraceFlags = $TraceFlag -join ','
                    $parameterString += (($TraceFlag.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            } else {
                if ('TraceFlag' -in $__boundParams.Keys) {
                    if ($null -eq $TraceFlag) { $TraceFlag = '' }
                    $oldFlags = @($currentStartup.TraceFlags) -split ',' | Where-Object { $_ -ne 'None' }
                    $newFlags = $TraceFlag
                    $newStartup.TraceFlags = (@($oldFlags) + @($newFlags) | Sort-Object -Unique) -join ','
                } elseif ($TraceFlagOverride) {
                    $newStartup.TraceFlags = ''
                } else {
                    $newStartup.TraceFlags = if ($currentStartup.TraceFlags -eq 'None') { }
                    else { $currentStartup.TraceFlags -join ',' }
                }
                If ($newStartup.TraceFlags.Length -ne 0) {
                    $parameterString += (($newStartup.TraceFlags.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            }
"""";
}
