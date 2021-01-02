function Set-DbaStartupParameter {
    <#
    .SYNOPSIS
        Sets the Startup Parameters for a SQL Server instance

    .DESCRIPTION
        Modifies the startup parameters for a specified SQL Server Instance

        For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

    .PARAMETER SqlInstance
        The SQL Server instance to be modified

        If the Sql Instance is offline path parameters will be ignored as we cannot test the instance's access to the path. If you want to force this to work then please use the Force switch

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER MasterData
        Path to the data file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER MasterLog
        Path to the log file for the Master database

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER ErrorLog
        Path to the SQL Server error log file

        Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

    .PARAMETER TraceFlag
        A comma separated list of TraceFlags to be applied at SQL Server startup
        By default these will be appended to any existing trace flags set

    .PARAMETER CommandPromptStart
        Shortens startup time when starting SQL Server from the command prompt. Typically, the SQL Server Database Engine starts as a service by calling the Service Control Manager.
        Because the SQL Server Database Engine does not start as a service when starting from the command prompt

    .PARAMETER MinimalStart
        Starts an instance of SQL Server with minimal configuration. This is useful if the setting of a configuration value (for example, over-committing memory) has
        prevented the server from starting. Starting SQL Server in minimal configuration mode places SQL Server in single-user mode

    .PARAMETER MemoryToReserve
        Specifies an integer number of megabytes (MB) of memory that SQL Server will leave available for memory allocations within the SQL Server process,
        but outside the SQL Server memory pool. The memory outside of the memory pool is the area used by SQL Server for loading items such as extended procedure .dll files,
        the OLE DB providers referenced by distributed queries, and automation objects referenced in Transact-SQL statements. The default is 256 MB.

    .PARAMETER SingleUser
        Start Sql Server in single user mode

    .PARAMETER NoLoggingToWinEvents
        Don't use Windows Application events log

    .PARAMETER StartAsNamedInstance
        Allows you to start a named instance of SQL Server

    .PARAMETER DisableMonitoring
        Disables the following monitoring features:

        SQL Server performance monitor counters
        Keeping CPU time and cache-hit ratio statistics
        Collecting information for the DBCC SQLPERF command
        Collecting information for some dynamic management views
        Many extended-events event points

        ** Warning *\* When you use the -x startup option, the information that is available for you to diagnose performance and functional problems with SQL Server is greatly reduced.

    .PARAMETER SingleUserDetails
        The username for single user

    .PARAMETER IncreasedExtents
        Increases the number of extents that are allocated for each file in a file group.

    .PARAMETER TraceFlagOverride
        Overrides the default behaviour and replaces any existing trace flags. If not trace flags specified will just remove existing ones

    .PARAMETER StartupConfig
        Pass in a previously saved SQL Instance startup config
        using this parameter will set TraceFlagOverride to true, so existing Trace Flags will be overridden

    .PARAMETER Offline
        Setting this switch will try perform the requested actions without connect to the SQL Server Instance, this will speed things up if you know the Instance is offline.

        When working offline, path inputs (MasterData, MasterLog and ErrorLog) will be ignored, unless Force is specified

    .PARAMETER Force
        By default we test the values passed in via MasterData, MasterLog, ErrorLog

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Startup, Parameter, Configure
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaStartupParameter

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser

        Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -IncreasedExtents

        Will configure the SQL Instance sql2016 to IncreasedExtents = True (-E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016  -IncreasedExtents:$false -WhatIf

        Shows what would happen if you attempted to configure the SQL Instance sql2016 to IncreasedExtents = False (no -E)

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -TraceFlag 8032,8048

        This will append Trace Flags 8032 and 8048 to the startup parameters

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride

        This will remove all trace flags and set SingleUser to false

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlag 8032,8048 -TraceFlagOverride

        This will set Trace Flags 8032 and 8048 to the startup parameters, removing any existing Trace Flags

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagOverride -Offline

        This will remove all trace flags and set SingleUser to false from an offline instance

    .EXAMPLE
        PS C:\> Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline

        This will attempt to change the ErrorLog path to c:\sql\. However, with the offline switch this will not happen. To force it, use the -Force switch like so:

        Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline -Force

    .EXAMPLE
        PS C:\> $StartupConfig = Get-DbaStartupParameter -SqlInstance server1\instance1
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -NoLoggingToWinEvents
        PS C:\> #Restart your SQL instance with the tool of choice
        PS C:\> #Do Some work
        PS C:\> Set-DbaStartupParameter -SqlInstance server1\instance1 -StartupConfig $StartupConfig
        PS C:\> #Restart your SQL instance with the tool of choice and you're back to normal

        In this example we take a copy of the existing startup configuration of server1\instance1

        We then change the startup parameters ahead of some work

        After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param ([parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$MasterData,
        [string]$MasterLog,
        [string]$ErrorLog,
        [string[]]$TraceFlag,
        [switch]$CommandPromptStart,
        [switch]$MinimalStart,
        [int]$MemoryToReserve,
        [switch]$SingleUser,
        [string]$SingleUserDetails,
        [switch]$NoLoggingToWinEvents,
        [switch]$StartAsNamedInstance,
        [switch]$DisableMonitoring,
        [switch]$IncreasedExtents,
        [switch]$TraceFlagOverride,
        [object]$StartupConfig,
        [switch]$Offline,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        $null = Test-ElevationRequirement -ComputerName $SqlInstance[0]
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if (-not $Offline) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Write-Message -Level Warning -Message "Failed to connect to $instance, will try to work with just WMI. Path options will be ignored unless Force was indicated"
                    $Server = $instance
                    $Offline = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Offline switch set, proceeding with just WMI"
                $server = $instance
            }

            # Get Current parameters (uses WMI) -- requires elevated session
            try {
                $currentStartup = Get-DbaStartupParameter -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Unable to gather current startup parameters" -Target $instance -ErrorRecord $_
                return
            }
            $originalParamString = $currentStartup.ParameterString

            Write-Message -Level Verbose -Message "Original startup parameter string: $originalParamString"

            if ('StartupConfig' -in $PSBoundParameters.Keys) {
                Write-Message -Level VeryVerbose -Message "startupObject passed in"
                $newStartup = $StartupConfig
                $TraceFlagOverride = $true
            } else {
                Write-Message -Level VeryVerbose -Message "Parameters passed in"
                $newStartup = $currentStartup.PSObject.Copy()
                foreach ($param in ($PSBoundParameters.Keys | Where-Object { $_ -in ($newStartup.PSObject.Properties.Name) })) {
                    if ($PSBoundParameters.Item($param) -ne $newStartup.$param) {
                        $newStartup.$param = $PSBoundParameters.Item($param)
                    }
                }
            }

            if (!($currentStartup.SingleUser)) {

                if ($newStartup.MasterData.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterData path"
                        $parameterString += "-d$($currentStartup.MasterData);"

                    } else {
                        if ($Force) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterData -Parent)) {
                            $parameterString += "-d$($newStartup.MasterData);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterData file is not reachable by instance $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterData value must be provided"
                    return
                }

                if ($newStartup.ErrorLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested ErrorLog path"
                        $parameterString += "-e$($currentStartup.ErrorLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.ErrorLog -Parent)) {
                            $parameterString += "-e$($newStartup.ErrorLog);"
                        } else {
                            Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "ErrorLog value must be provided"
                    return
                }

                if ($newStartup.MasterLog.Length -gt 0) {
                    if ($Offline -and -not $Force) {
                        Write-Message -Level Warning -Message "Working offline, skipping untested MasterLog path"
                        $parameterString += "-l$($currentStartup.MasterLog);"
                    } else {
                        if ($Force) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } elseif (Test-DbaPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newStartup.MasterLog -Parent)) {
                            $parameterString += "-l$($newStartup.MasterLog);"
                        } else {
                            Stop-Function -Message "Specified folder for MasterLog  file is not reachable by $instance"
                            return
                        }
                    }
                } else {
                    Stop-Function -Message "MasterLog value must be provided."
                    return
                }
            } else {

                Write-Message -Level Verbose -Message "Instance is presently configured for single user, skipping path validation"
                if ($newStartup.MasterData.Length -gt 0) {
                    $parameterString += "-d$($newStartup.MasterData);"
                } else {
                    Stop-Function -Message "Must have a value for MasterData"
                    return
                }
                if ($newStartup.ErrorLog.Length -gt 0) {
                    $parameterString += "-e$($newStartup.ErrorLog);"
                } else {
                    Stop-Function -Message "Must have a value for Errorlog"
                    return
                }
                if ($newStartup.MasterLog.Length -gt 0) {
                    $parameterString += "-l$($newStartup.MasterLog);"
                } else {
                    Stop-Function -Message "Must have a value for MasterLog"
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
            if ($TraceFlagOverride -and 'TraceFlag' -in $PSBoundParameters.Keys) {
                if ($null -ne $TraceFlag -and '' -ne $TraceFlag) {
                    $newStartup.TraceFlags = $TraceFlag -join ','
                    $parameterString += (($TraceFlag.Split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
                }
            } else {
                if ('TraceFlag' -in $PSBoundParameters.Keys) {
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

                        $output = Get-DbaStartupParameter -SqlInstance $server.ComputerName -Credential $Credential -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                    } else {
                        $null = Invoke-ManagedComputerCommand -ComputerName $server.ComputerName -scriptBlock $scriptBlock -ArgumentList $server.ComputerName, $displayName, $parameterString -EnableException

                        $output = Get-DbaStartupParameter -SqlInstance $server.ComputerName -EnableException
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalParamString
                        Add-Member -Force -InputObject $output -MemberType NoteProperty -Name Notes -Value "Startup parameters changed on $instance. You must restart SQL Server for changes to take effect."
                    }
                    $output
                } catch {
                    Stop-Function -Message "Startup parameter update failed on $instance. " -Target $instance -ErrorRecord $_
                    return
                }
            }
        }
    }
}