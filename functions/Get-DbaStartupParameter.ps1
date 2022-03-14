function Get-DbaStartupParameter {
    <#
    .SYNOPSIS
        Displays values for a detailed list of SQL Server Startup Parameters.

    .DESCRIPTION
        Displays values for a detailed list of SQL Server Startup Parameters including Master Data Path, Master Log path, Error Log, Trace Flags, Parameter String and much more.

        This command relies on remote Windows Server (SQL WMI/WinRm) access. You can pass alternative Windows credentials by using the -Credential parameter.

        See https://msdn.microsoft.com/en-us/library/ms190737.aspx for more information.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Allows you to login to servers using alternate Windows credentials.

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Simple
        If this switch is enabled, simplified output will be produced including only Server, Master Data path, Master Log path, ErrorLog, TraceFlags and ParameterString.

    .PARAMETER EnableException
        If this switch is enabled, exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

    .NOTES
        Tags: WSMan, SQLWMI, Memory, Startup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaStartupParameter

    .EXAMPLE
        PS C:\> Get-DbaStartupParameter -SqlInstance sql2014

        Logs into SQL WMI as the current user then displays the values for numerous startup parameters.

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> Get-DbaStartupParameter -SqlInstance sql2014 -Credential $wincred -Simple

        Logs in to WMI using the ad\sqladmin credential and gathers simplified information about the SQL Server Startup Parameters.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("SqlCredential")]
        [PSCredential]$Credential,
        [switch]$Simple,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $computerName = $instance.ComputerName
                $instanceName = $instance.InstanceName
                $ogInstance = $instance.FullSmoName

                $computerName = (Resolve-DbaNetworkName -ComputerName $computerName).FullComputerName


                if ($instanceName.Length -eq 0) { $instanceName = "MSSQLSERVER" }

                $displayName = "SQL Server ($instanceName)"

                $scriptBlock = {
                    $computerName = $args[0]
                    $displayName = $args[1]

                    $wmisvc = $wmi.Services | Where-Object DisplayName -eq $displayName

                    $params = $wmisvc.StartupParameters -split ';'

                    $masterData = $params | Where-Object { $_.StartsWith('-d') }
                    $masterLog = $params | Where-Object { $_.StartsWith('-l') }
                    $errorLog = $params | Where-Object { $_.StartsWith('-e') }
                    $traceFlags = $params | Where-Object { $_.StartsWith('-T') }

                    $debugflag = $params | Where-Object { $_.StartsWith('-t') }

                    if ($debugflag.length -ne 0) {
                        Write-Message -Level Warning "$instance is using the lowercase -t trace flag. This is for internal debugging only. Please ensure this was intentional."
                    }
                    #>

                    if ($traceFlags.length -eq 0) {
                        $traceFlags = "None"
                    } else {
                        [int[]]$traceFlags = $traceFlags.substring(2)
                    }

                    if ($Simple -eq $true) {
                        [PSCustomObject]@{
                            ComputerName    = $computerName
                            InstanceName    = $instanceName
                            SqlInstance     = $ogInstance
                            MasterData      = $masterData.TrimStart('-d')
                            MasterLog       = $masterLog.TrimStart('-l')
                            ErrorLog        = $errorLog.TrimStart('-e')
                            TraceFlags      = $traceFlags
                            ParameterString = $wmisvc.StartupParameters
                        }
                    } else {
                        # From https://msdn.microsoft.com/en-us/library/ms190737.aspx

                        $commandPromptParm = $params | Where-Object { $_ -eq '-c' }
                        $minimalStartParm = $params | Where-Object { $_ -eq '-f' }
                        $memoryToReserve = $params | Where-Object { $_.StartsWith('-g') }
                        $noEventLogsParm = $params | Where-Object { $_ -eq '-n' }
                        $instanceStartParm = $params | Where-Object { $_ -eq '-s' }
                        $disableMonitoringParm = $params | Where-Object { $_ -eq '-x' }
                        $increasedExtentsParm = $params | Where-Object { $_ -ceq '-E' }

                        $minimalStart = $noEventLogs = $instanceStart = $disableMonitoring = $false
                        $increasedExtents = $commandPrompt = $singleUser = $false

                        if ($null -ne $commandPromptParm) {
                            $commandPrompt = $true
                        }
                        if ($null -ne $minimalStartParm) {
                            $minimalStart = $true
                        }
                        if ($null -eq $memoryToReserve) {
                            $memoryToReserve = 0
                        }
                        if ($null -ne $noEventLogsParm) {
                            $noEventLogs = $true
                        }
                        if ($null -ne $instanceStartParm) {
                            $instanceStart = $true
                        }
                        if ($null -ne $disableMonitoringParm) {
                            $disableMonitoring = $true
                        }
                        if ($null -ne $increasedExtentsParm) {
                            $increasedExtents = $true
                        }

                        $singleUserParm = $params | Where-Object { $_.StartsWith('-m') }

                        if ($singleUserParm.length -ne 0) {
                            $singleUser = $true
                            $singleUserDetails = $singleUserParm.TrimStart('-m')
                        }

                        [PSCustomObject]@{
                            ComputerName         = $computerName
                            InstanceName         = $instanceName
                            SqlInstance          = $ogInstance
                            MasterData           = $masterData -replace '^-[dD]', ''
                            MasterLog            = $masterLog -replace '^-[lL]', ''
                            ErrorLog             = $errorLog -replace '^-[eE]', ''
                            TraceFlags           = $traceFlags
                            CommandPromptStart   = $commandPrompt
                            MinimalStart         = $minimalStart
                            MemoryToReserve      = $memoryToReserve
                            SingleUser           = $singleUser
                            SingleUserName       = $singleUserDetails
                            NoLoggingToWinEvents = $noEventLogs
                            StartAsNamedInstance = $instanceStart
                            DisableMonitoring    = $disableMonitoring
                            IncreasedExtents     = $increasedExtents
                            ParameterString      = $wmisvc.StartupParameters
                        }
                    }
                }

                # This command is in the internal function
                # It's sorta like Invoke-Command.
                if ($credential) {
                    Invoke-ManagedComputerCommand -Server $computerName -Credential $credential -ScriptBlock $scriptBlock -ArgumentList $computerName, $displayName
                } else {
                    Invoke-ManagedComputerCommand -Server $computerName -ScriptBlock $scriptBlock -ArgumentList $computerName, $displayName
                }
            } catch {
                Stop-Function -Message "$instance failed." -ErrorRecord $_ -Continue -Target $instance
            }
        }
    }
}
