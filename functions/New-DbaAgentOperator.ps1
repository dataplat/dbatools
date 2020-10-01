function New-DbaAgentOperator {
    <#
    .SYNOPSIS
        New-DbaAgentOperator creates a new operator on an instance.

    .DESCRIPTION
        If the operator already exists on the destination, it will not be created unless -Force is used.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OperatorName
        Name of the operator in SQL Agent.

    .PARAMETER EmailAddress
        The email address the SQL Agent will use to email alerts to the operator.

    .PARAMETER NetSendAddress
        The net send address the SQL Agent will use for the operator to net send alerts.

    .PARAMETER PagerAddress
        The pager email address the SQL Agent will use to send alerts to the oeprator.

    .PARAMETER PagerDays
        Defines what days the pager portion of the operator will be used. The default is 'Everyday'. Valid parameters
        are 'EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', and
        'Saturday'.

     .PARAMETER SaturdayStartTime
        This an string that takes the Saturday Pager Start Time.

    .PARAMETER SaturdayEndTime
        This an string that takes the Saturday Pager End Time.

    .PARAMETER SundayStartTime
        This an string that takes the Sunday Pager Start Time.

    .PARAMETER SundayEndTime
        This an string that takes the Sunday Pager End Time.

    .PARAMETER WeekdayStartTime
        This an string that takes the Weekdays Pager Start Time.

    .PARAMETER WeekdayEndTime
        This an string that takes the Weekdays Pager End Time.

    .PARAMETER IsFailSafeOperator
        If this switch is enabled, this operator will be your failsafe operator and replace the one that existed before.

    .PARAMETER FailsafeNotificationMethod
        Deinfes the notifcation method for notifiy the failsafe oeprator.  Value must be NofityMail or NotifyPager.
        The default is NotifyEmail.

    .PARAMETER Force
        If this switch is enabled, the Operator will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Operator
        Author: Tracy Boggiano (@TracyBoggiano), databasesuperhero.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/New-DbaAgentOperator

    .EXAMPLE
        PS:> New-DbaAgentOperator $SQLInstance localhost -OperatorName "DBA" -OperatorEmail "operator@operator.com" -$PagerDays "Everday" -Force

        This sets a new operator named DBA with the above email address with default values to alerts everyday
        for all hours of the day.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SQLInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$OperatorName,
        [string]$EmailAddress,
        [string]$NetSendAddress,
        [string]$PagerAddress,
        [ValidateSet('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$PagerDays,
        [string]$SaturdayStartTime,
        [string]$SaturdayEndTime,
        [string]$SundayStartTime,
        [string]$SundayEndTime,
        [string]$WeekendStartTime,
        [string]$WeekendEndTime,
        [switch]$IsFailsafeOperator = $false,
        [string]$FailsafeNotificationMethod = "NotifyEmail",
        [switch]$Force = $false,
        [switch]$EnableException
    )

    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SQLInstance -SqlCredential $serverSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SQLInstance" -Category ConnectionError -ErrorRecord $_ -Target $SQLInstance
            return
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ($null -eq $EmailAddress -and $null -eq $NetSendAddress -and $null -eq $PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator."
            return
        }

        [int]$Interval = 0

        # Loop through the array
        foreach ($Item in $PagerDays) {
            switch ($Item) {
                "Sunday" { $Interval += 1 }
                "Monday" { $Interval += 2 }
                "Tuesday" { $Interval += 4 }
                "Wednesday" { $Interval += 8 }
                "Thursday" { $Interval += 16 }
                "Friday" { $Interval += 32 }
                "Saturday" { $Interval += 64 }
                "Weekdays" { $Interval = 62 }
                "Weekend" { $Interval = 65 }
                "EveryDay" { $Interval = 127 }
                1 { $Interval += 1 }
                2 { $Interval += 2 }
                4 { $Interval += 4 }
                8 { $Interval += 8 }
                16 { $Interval += 16 }
                32 { $Interval += 32 }
                64 { $Interval += 64 }
                62 { $Interval = 62 }
                65 { $Interval = 65 }
                127 { $Interval = 127 }
                default { $Interval = 0 }
            }
        }

        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        # Check the start time
        if (-not $SaturdayStartTime -and $Force) {
            $SaturdayStartTime = '000000'
            Write-Message -Message "Saturday Start time was not set. Force is being used. Setting it to $SaturdayStartTime" -Level Verbose
        } elseif (-not $SaturdayStartTime -and $PagerDays -in ('Everyday', 'Saturday', 'Weekends')) {
            Stop-Function -Message "Please enter Saturday start time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($SaturdayStartTime -notmatch $RegexTime) {
            Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time
        if (-not $SaturdayEndTime -and $Force) {
            $SaturdayEndTime = '235959'
            Write-Message -Message "Saturday End time was not set. Force is being used. Setting it to $SaturdayEndTime" -Level Verbose
        } elseif (-not $SaturdayEndTime -and $PagerDays -in ('Everyday', 'Saturday', 'Weekends')) {
            Stop-Function -Message "Please enter a Saturday end time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($SaturdayEndTime -notmatch $RegexTime) {
            Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the start time
        if (-not $SundayStartTime -and $Force) {
            $SundayStartTime = '000000'
            Write-Message -Message "Sunday Start time was not set. Force is being used. Setting it to $SundayStartTime" -Level Verbose
        } elseif (-not $SundayStartTime -and $PagerDays -in ('Everyday', 'Sunday', 'Weekends')) {
            Stop-Function -Message "Please enter a Sunday start time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($SundayStartTime -notmatch $RegexTime) {
            Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  `1"
        if (-not $SundayEndTime -and $Force) {
            $SundayEndTime = '235959'
            Write-Message -Message "Sunday End time was not set. Force is being used. Setting it to $SundayEndTime" -Level Verbose
        } elseif (-not $SundayEndTime -and $PagerDays -in ('Everyday', 'Sunday', 'Weekends')) {
            Stop-Function -Message "Please enter a Sunday End Time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($SundayEndTime -notmatch $RegexTime) {
            Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the start time
        if (-not $WeekdayStartTime -and $Force) {
            $WeekdayStartTime = '000000'
            Write-Message -Message "Weekday Start time was not set. Force is being used. Setting it to $WeekdayStartTime" -Level Verbose
        } elseif (-not $WeekdayStartTime -and $PagerDays -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            Stop-Function -Message "Please enter Weekday Start Time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($WeekdayStartTime -notmatch $RegexTime) {
            Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time
        if (-not $WeekdayEndTime -and $Force) {
            $WeekdayEndTime = '235959'
            Write-Message -Message "Weekday End time was not set. Force is being used. Setting it to $WeekdayEndTime" -Level Verbose
        } elseif (-not $WeekdayEndTime -and $PagerDays -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            Stop-Function -Message "Please enter a Weekday End Time or use -Force to use defaults." -Target $SqlInstance
            return
        } elseif ($WeekdayEndTime -notmatch $RegexTime) {
            Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod -notin ('NofityMail', 'NotifyPager'))) {
            Stop-Function -Message "You must specify a notifiation method for the failsafe operator."
            return
        }

        #Format times
        if ($SaturdayStartTime) {
            $SaturdayStartTime = $SaturdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SaturdayEndTime) {
            $SaturdayEndTime = $SaturdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($SundayStartTime) {
            $SundayStartTime = $SundayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($SundayEndTime) {
            $SundayEndTime = $SundayEndTime.Insert(4, ':').Insert(2, ':')
        }

        if ($WeekdayStartTime) {
            $WeekdayStartTime = $WeekdayStartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($WeekdayEndTime) {
            $WeekdayEndTime = $WeekdayEndTime.Insert(4, ':').Insert(2, ':')
        }

        $failsafe = $server.JobServer.AlertSystem | Select-Object FailSafeOperator

        if ((Get-DbaAgentOperator -SQLInstance $SQLInstance -Operator $OperatorName).Count -ne 0) {
            if ($force -eq $false) {
                if ($Pscmdlet.ShouldProcess($SQLInstance, "Operator $operatorName exists at on $SQLInstance. Use -Force to drop and and create it.")) {
                    Write-Message -Level Verbose -Message "Operator $operatorName exists at $SQLInstance. Use -Force to drop and create."
                }
                continue
            } else {
                if ($failsafe.FailSafeOperator -eq $operatorName -and $IsFailsafeOperator) {
                    Write-Message -Level Verbose -Message "$operatorName is the failsafe operator. Skipping drop."
                    continue
                }

                if ($Pscmdlet.ShouldProcess($SQLInstance, "Dropping operator $operatorName")) {
                    try {
                        Write-Message -Level Verbose -Message "Dropping Operator $operatorName"
                        $server.JobServer.Operators[$operatorName].Drop()
                    } catch {
                        Stop-Function -Message "Issue dropping operator" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                    }
                }
            }
        }

        if ($Pscmdlet.ShouldProcess($SQLInstance, "Creating Operator $operatorName")) {
            try {
                $operator = New-Object ('Microsoft.SqlServer.Management.Smo.Agent.Operator') ($server.JobServer, $OperatorName)

                $operator.Name = $OperatorName
                $operator.EmailAddress = $EmailAddress
                $operator.NetSendAddress = $NetSendAddress
                $operator.PagerAddress = $PagerAddress
                $operator.PagerDays = $Interval
                $operator.SaturdayPagerStartTime = $SaturdayStartTime
                $operator.SaturdayPagerEndTime = $SaturdayEndTime
                $operator.SundayPagerStartTime = $SundayStartTime
                $operator.SundayPagerEndTime = $SundayEndTime
                $operator.WeekdayPagerStartTime = $WeekdayStartTime
                $operator.WeekdayPagerEndTime = $WeekdayEndTime

                $operator.Create()

                if ($IsFailsafeOperator) {
                    $server.JobServer.AlertSystem.FailSafeOperator = $IsFailsafeOperator
                    $server.JobServer.AlertSystem.FailSafeOperator.NotificationMethod = $FailsafeNoficationMethod
                    $server.JobServer.AlertSystem.Alter()
                }

                Write-Message -Level Verbose -Message "Creating Operator $operatorName"
                Get-DbaAgentOperator -SqlInstance $SQLInstance -Operator $OperatorName
            } catch {
                Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $SQLInstance
            }
        }
    }
}