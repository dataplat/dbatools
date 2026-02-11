function Set-DbaStartupParameter {
    <#
    .SYNOPSIS
        Modifies SQL Server startup parameters stored in the Windows registry

    .DESCRIPTION
        Changes the startup parameters that SQL Server uses when the service starts, including paths to master database files, error log location, and various startup flags. These parameters are stored in the Windows registry and require elevated permissions to modify.

        This function is commonly used to enable single-user mode for emergency repairs, set trace flags for troubleshooting, relocate system database files during migrations, or adjust memory settings. Changes take effect only after the SQL Server service is restarted.

        The function validates file paths when the instance is online to prevent startup failures, but can work offline with the -Force parameter when you need to modify parameters for instances that won't start.

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
        Specifies the file path to the master database data file (master.mdf). Required when relocating system databases or recovering from corrupted system files.
        Use this when moving SQL Server installations, restoring from backup to different locations, or troubleshooting startup issues caused by missing or corrupted master database files. The path must be accessible by the SQL Server service account.
        Will be ignored if SqlInstance is offline unless the Force parameter is used, as the function validates the path accessibility when the instance is online.

    .PARAMETER MasterLog
        Specifies the file path to the master database log file (mastlog.ldf). Required when relocating system databases or recovering from corrupted system files.
        Use this alongside MasterData when moving SQL Server installations or troubleshooting startup failures related to master database corruption. The path must be accessible by the SQL Server service account.
        Will be ignored if SqlInstance is offline unless the Force parameter is used, as the function validates the path accessibility when the instance is online.

    .PARAMETER ErrorLog
        Specifies the file path where SQL Server will write its error log files. Controls where diagnostic information, startup messages, and error details are stored.
        Use this when you need to redirect error logs to a different drive for space management, centralized logging, or compliance requirements. The directory must exist and be writable by the SQL Server service account.
        Will be ignored if SqlInstance is offline unless the Force parameter is used, as the function validates the path accessibility when the instance is online.

    .PARAMETER TraceFlag
        Specifies one or more trace flags to enable at SQL Server startup as a comma-separated list. Trace flags control specific SQL Server behaviors and diagnostic features.
        Use this for enabling global trace flags like 1117 (uniform extent allocations), 1118 (reduce tempdb contention), or 3226 (suppress successful backup messages). By default, these flags are appended to existing trace flags.
        Use TraceFlagOverride parameter to replace all existing trace flags instead of appending to them.

    .PARAMETER CommandPromptStart
        Enables faster startup when SQL Server is launched from command prompt rather than as a Windows service. Bypasses Service Control Manager initialization routines.
        Use this when you need to start SQL Server manually for troubleshooting or testing scenarios where you'll be running sqlservr.exe directly from command line instead of using service management tools.

    .PARAMETER MinimalStart
        Starts SQL Server with minimal configuration, loading only essential components and services. Automatically places the instance in single-user mode with reduced functionality.
        Use this when SQL Server won't start normally due to configuration problems like excessive memory allocation, corrupted configuration settings, or problematic startup procedures. Essential for emergency recovery scenarios.
        Note that many features will be unavailable in minimal start mode, making it suitable only for troubleshooting and corrective actions.

    .PARAMETER MemoryToReserve
        Specifies the amount of memory in megabytes to reserve outside the SQL Server buffer pool for system components and extended procedures.
        Use this when experiencing out-of-memory errors related to extended procedures, OLE DB providers, or CLR assemblies, especially on systems with large amounts of RAM allocated to SQL Server. The reserved memory hosts DLL files, distributed query providers, and automation objects.
        Default value is 256 MB, but you may need to increase this on servers with heavy use of extended procedures or CLR integration.

    .PARAMETER SingleUser
        Starts SQL Server in single-user mode, allowing only one connection at a time. Prevents other users and applications from connecting to the instance.
        Use this for emergency maintenance, database recovery operations, or when you need exclusive access to troubleshoot corruption or perform administrative tasks that require isolation.
        Combine with SingleUserDetails parameter to restrict access to a specific login for additional security during maintenance windows.

    .PARAMETER NoLoggingToWinEvents
        Disables SQL Server from writing startup and shutdown messages to the Windows Application Event Log. Only affects system event logging, not SQL Server error log files.
        Use this to reduce event log clutter in environments with frequent SQL Server restarts or when centralized logging systems capture SQL Server events through other means.
        SQL Server will continue writing to its own error log files regardless of this setting.

    .PARAMETER StartAsNamedInstance
        Enables starting a named instance of SQL Server, ensuring proper instance identification and network connectivity for non-default instances.
        Use this when configuring startup parameters for named instances that need to be explicitly identified during startup to avoid conflicts with default instances or other named instances on the same server.
        Required for named instances to register properly with SQL Server Browser service and establish correct network endpoints.

    .PARAMETER DisableMonitoring
        Disables SQL Server's internal performance monitoring and statistics collection to reduce overhead on high-performance systems.
        Use this only on production systems where every bit of performance matters and you have alternative monitoring solutions in place. Disables PerfMon counters, CPU statistics, cache-hit ratios, DBCC SQLPERF data, some DMVs, and many extended events.
        Warning: This significantly reduces your ability to diagnose performance issues and should only be used when monitoring overhead is confirmed to impact critical workloads.

    .PARAMETER SingleUserDetails
        Specifies which login or application can connect when SQL Server is in single-user mode. Restricts the single connection to a specific user account.
        Use this to ensure only authorized personnel can access the instance during maintenance windows, preventing applications or other users from grabbing the single available connection.
        Can specify a login name, domain account, or application name. Automatically quoted if the value contains spaces.

    .PARAMETER IncreasedExtents
        Increases the number of extents allocated for each file in a file group, improving allocation efficiency for databases with multiple data files.
        Use this on systems with multiple data files per filegroup to reduce allocation contention and improve performance during heavy insert/update operations.
        Particularly beneficial for tempdb configurations with multiple data files or user databases designed with multiple files for performance.

    .PARAMETER TraceFlagOverride
        Replaces all existing trace flags with only the ones specified in the TraceFlag parameter. Without this switch, new trace flags are appended to existing ones.
        Use this when you need to completely reset the trace flag configuration or remove problematic trace flags that are causing issues.
        If no TraceFlag values are provided with this switch, all existing trace flags will be removed from the startup parameters.

    .PARAMETER StartupConfig
        Applies a complete startup configuration object previously captured with Get-DbaStartupParameter. Restores all startup parameters to match the saved configuration.
        Use this to quickly restore previous startup configurations after troubleshooting, rollback changes during maintenance, or standardize startup parameters across multiple instances.
        Automatically enables TraceFlagOverride, so all existing trace flags will be replaced with those from the saved configuration.

    .PARAMETER Offline
        Performs startup parameter changes without attempting to connect to the SQL Server instance, improving performance when you know the instance is not running.
        Use this when modifying startup parameters for instances that are intentionally stopped or when you want to avoid connection overhead on known offline instances.
        When using this switch, file path parameters (MasterData, MasterLog, ErrorLog) cannot be validated and will be ignored unless the Force parameter is also specified.

    .PARAMETER Force
        Bypasses file path validation for MasterData, MasterLog, and ErrorLog parameters, allowing changes even when paths cannot be verified.
        Use this when configuring startup parameters for offline instances or when you need to set paths that will be valid after a restart but are not currently accessible.
        Exercise caution as invalid paths will prevent SQL Server from starting, requiring manual registry editing to correct.

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

    .OUTPUTS
        PSCustomObject

        Returns the startup parameter object from Get-DbaStartupParameter with additional NoteProperty members added.

        Base properties (from Get-DbaStartupParameter):
        - ComputerName (string) - The name of the computer hosting the SQL Server instance
        - InstanceName (string) - The SQL Server instance name
        - SqlInstance (string) - The full SQL Server instance name
        - MasterData (string) - Path to master database data file (-d parameter)
        - MasterLog (string) - Path to master database log file (-l parameter)
        - ErrorLog (string) - Path to the error log file (-e parameter)
        - TraceFlags (string) - Comma-separated list of enabled trace flags (-T parameters)
        - DebugFlags (string) - Debug flags if any are set
        - CommandPromptStart (boolean) - Whether command prompt start flag (-c) is enabled
        - MinimalStart (boolean) - Whether minimal start flag (-f) is enabled
        - MemoryToReserve (int) - Memory reserved in MB (-g parameter)
        - SingleUser (boolean) - Whether single-user mode (-m) is enabled
        - SingleUserName (string) - Specific login allowed in single-user mode (if specified)
        - NoLoggingToWinEvents (boolean) - Whether Windows event logging is disabled (-n)
        - StartAsNamedInstance (boolean) - Whether named instance flag (-s) is enabled
        - DisableMonitoring (boolean) - Whether performance monitoring is disabled (-x)
        - IncreasedExtents (boolean) - Whether increased extents flag (-E) is enabled
        - ParameterString (string) - Complete startup parameter string as stored in registry

        Added NoteProperty members:
        - OriginalStartupParameters (string) - The startup parameter string before any modifications (always added)
        - Notes (string) - Message indicating changes were made and restart is required (added when Credential parameter is not provided)

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
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Write-Message -Level Warning -Message "Failed to connect to $instance, will try to work with just WMI. Path options will be ignored unless Force was indicated"
                    $server = $instance
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
            $parameterString = $null

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
                    Stop-Function -Message "Startup parameter update failed on $instance. " -Target $instance -ErrorRecord $_
                    return
                }
            }
        }
    }
}