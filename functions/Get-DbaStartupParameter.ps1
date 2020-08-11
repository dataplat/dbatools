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
        If this switch is enabled, simplified output will be produced including only Server, Master Data Path, Master Log path, ErrorLog, TraceFlags and ParameterString.

    .PARAMETER EnableException
        If this switch is enabled, exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

    .NOTES
        Tags: WSMan, SQLWMI, Memory
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

                $displayname = "SQL Server ($instanceName)"

                $Scriptblock = {
                    $computerName = $args[0]
                    $displayname = $args[1]

                    $wmisvc = $wmi.Services | Where-Object DisplayName -eq $displayname

                    $params = $wmisvc.StartupParameters -split ';'

                    $masterdata = $params | Where-Object { $_.StartsWith('-d') }
                    $masterlog = $params | Where-Object { $_.StartsWith('-l') }
                    $errorlog = $params | Where-Object { $_.StartsWith('-e') }
                    $traceflags = $params | Where-Object { $_.StartsWith('-T') }

                    $debugflag = $params | Where-Object { $_.StartsWith('-t') }

                    if ($debugflag.length -ne 0) {
                        Write-Message -Level Warning "$instance is using the lowercase -t trace flag. This is for internal debugging only. Please ensure this was intentional."
                    }
                    #>

                    if ($traceflags.length -eq 0) {
                        $traceflags = "None"
                    } else {
                        [int[]]$traceflags = $traceflags.substring(2)
                    }

                    if ($Simple -eq $true) {
                        [PSCustomObject]@{
                            ComputerName    = $computerName
                            InstanceName    = $instanceName
                            SqlInstance     = $ogInstance
                            MasterData      = $masterdata.TrimStart('-d')
                            MasterLog       = $masterlog.TrimStart('-l')
                            ErrorLog        = $errorlog.TrimStart('-e')
                            TraceFlags      = $traceflags
                            ParameterString = $wmisvc.StartupParameters
                        }
                    } else {
                        # From https://msdn.microsoft.com/en-us/library/ms190737.aspx

                        $commandpromptparm = $params | Where-Object { $_ -eq '-c' }
                        $minimalstartparm = $params | Where-Object { $_ -eq '-f' }
                        $memorytoreserve = $params | Where-Object { $_.StartsWith('-g') }
                        $noeventlogsparm = $params | Where-Object { $_ -eq '-n' }
                        $instancestartparm = $params | Where-Object { $_ -eq '-s' }
                        $disablemonitoringparm = $params | Where-Object { $_ -eq '-x' }
                        $increasedextentsparm = $params | Where-Object { $_ -ceq '-E' }

                        $minimalstart = $noeventlogs = $instancestart = $disablemonitoring = $false
                        $increasedextents = $commandprompt = $singleuser = $false

                        if ($null -ne $commandpromptparm) {
                            $commandprompt = $true
                        }
                        if ($null -ne $minimalstartparm) {
                            $minimalstart = $true
                        }
                        if ($null -eq $memorytoreserve) {
                            $memorytoreserve = 0
                        }
                        if ($null -ne $noeventlogsparm) {
                            $noeventlogs = $true
                        }
                        if ($null -ne $instancestartparm) {
                            $instancestart = $true
                        }
                        if ($null -ne $disablemonitoringparm) {
                            $disablemonitoring = $true
                        }
                        if ($null -ne $increasedextentsparm) {
                            $increasedextents = $true
                        }

                        $singleuserparm = $params | Where-Object { $_.StartsWith('-m') }

                        if ($singleuserparm.length -ne 0) {
                            $singleuser = $true
                            $singleuserdetails = $singleuserparm.TrimStart('-m')
                        }

                        [PSCustomObject]@{
                            ComputerName         = $computerName
                            InstanceName         = $instanceName
                            SqlInstance          = $ogInstance
                            MasterData           = $masterdata -replace '^-[dD]', ''
                            MasterLog            = $masterlog -replace '^-[lL]', ''
                            ErrorLog             = $errorlog -replace '^-[eE]', ''
                            TraceFlags           = $traceflags
                            CommandPromptStart   = $commandprompt
                            MinimalStart         = $minimalstart
                            MemoryToReserve      = $memorytoreserve
                            SingleUser           = $singleuser
                            SingleUserName       = $singleuserdetails
                            NoLoggingToWinEvents = $noeventlogs
                            StartAsNamedInstance = $instancestart
                            DisableMonitoring    = $disablemonitoring
                            IncreasedExtents     = $increasedextents
                            ParameterString      = $wmisvc.StartupParameters
                        }
                    }
                }

                # This command is in the internal function
                # It's sorta like Invoke-Command.
                if ($credential) {
                    Invoke-ManagedComputerCommand -Server $computerName -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $computerName, $displayname
                } else {
                    Invoke-ManagedComputerCommand -Server $computerName -ScriptBlock $Scriptblock -ArgumentList $computerName, $displayname
                }
            } catch {
                Stop-Function -Message "$instance failed." -ErrorRecord $_ -Continue -Target $instance
            }
        }
    }
}
