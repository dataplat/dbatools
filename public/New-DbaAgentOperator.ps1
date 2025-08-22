function New-DbaAgentOperator {
    <#
    .SYNOPSIS
        Creates a new SQL Server Agent operator with notification settings for alerts and job failures.

    .DESCRIPTION
        Creates SQL Server Agent operators who receive notifications when alerts fire or jobs fail. Operators are contacts that SQL Server Agent can notify via email, pager, or net send when specific events occur. You can configure pager schedules with different time windows for weekdays, weekends, and specific days to control when pager notifications are sent. This replaces the manual process of creating operators through SQL Server Management Studio and ensures consistent operator setup across multiple instances. If the operator already exists, it will not be created unless -Force is used to drop and recreate it.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        Name of the operator in SQL Agent.

    .PARAMETER EmailAddress
        The email address the SQL Agent will use to email alerts to the operator.

    .PARAMETER NetSendAddress
        The net send address the SQL Agent will use for the operator to net send alerts.

    .PARAMETER PagerAddress
        The pager email address the SQL Agent will use to send alerts to the oeprator.

    .PARAMETER PagerDay
        Defines what days the pager portion of the operator will be used. The default is 'Everyday'. Valid parameters
        are 'EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', and
        'Saturday'.

    .PARAMETER SaturdayStartTime
        This a string that takes the Saturday Pager Start Time.

    .PARAMETER SaturdayEndTime
        This a string that takes the Saturday Pager End Time.

    .PARAMETER SundayStartTime
        This a string that takes the Sunday Pager Start Time.

    .PARAMETER SundayEndTime
        This a string that takes the Sunday Pager End Time.

    .PARAMETER WeekdayStartTime
        This a string that takes the Weekdays Pager Start Time.

    .PARAMETER WeekdayEndTime
        This a string that takes the Weekdays Pager End Time.

    .PARAMETER IsFailsafeOperator
        If this switch is enabled, this operator will be your failsafe operator and replace the one that existed before.

    .PARAMETER FailsafeNotificationMethod
        Defines the notification method for the failsafe oeprator.  Value must be NotifyMail or NotifyPager.
        The default is NotifyEmail.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        If this switch is enabled, the Operator will be dropped and recreated on instance.

    .PARAMETER InputObject
        SMO Server Objects (pipeline input from Connect-DbaInstance)

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

    .LINK
        https://dbatools.io/New-DbaAgentOperator

    .EXAMPLE
        PS C:\> New-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com -PagerDay Everyday -Force

        This sets a new operator named DBA with the above email address with default values to alerts everyday
        for all hours of the day.

    .EXAMPLE
        PS C:\> New-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com `
        >>  -NetSendAddress dbauser1 -PagerAddress dbauser1@pager.dbatools.io -PagerDay Everyday `
        >>  -SaturdayStartTime 070000 -SaturdayEndTime 180000 -SundayStartTime 080000 `
        >>  -SundayEndTime 170000 -WeekdayStartTime 060000 -WeekdayEndTime 190000

        Creates a new operator named DBA on the sql01 instance with email address operator@operator.com, net send address of dbauser1, pager address of dbauser1@pager.dbatools.io, page day as every day, Saturday start time of 7am, Saturday end time of 6pm, Sunday start time of 8am, Sunday end time of 5pm, Weekday start time of 6am, and Weekday end time of 7pm.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Operator,
        [string]$EmailAddress,
        [string]$NetSendAddress,
        [string]$PagerAddress,
        [ValidateSet('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$PagerDay,
        [string]$SaturdayStartTime,
        [string]$SaturdayEndTime,
        [string]$SundayStartTime,
        [string]$SundayEndTime,
        [string]$WeekdayStartTime,
        [string]$WeekdayEndTime,
        [switch]$IsFailsafeOperator = $false,
        [string]$FailsafeNotificationMethod = "NotifyEmail",
        [switch]$Force = $false,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        if ($null -eq $EmailAddress -and $null -eq $NetSendAddress -and $null -eq $PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator."
            return
        }

        [int]$Interval = 0

        # Loop through the array
        foreach ($Item in $PagerDay) {
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

        if ($PagerDay -in ('Everyday', 'Saturday', 'Weekends')) {
            # Check the start time
            if (-not $SaturdayStartTime -and $Force) {
                $SaturdayStartTime = '000000'
                Write-Message -Message "Saturday Start time was not set. Force is being used. Setting it to $SaturdayStartTime" -Level Verbose
            } elseif (-not $SaturdayStartTime) {
                Stop-Function -Message "Please enter Saturday start time or use -Force to use defaults."
                return
            } elseif ($SaturdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }

            # Check the end time
            if (-not $SaturdayEndTime -and $Force) {
                $SaturdayEndTime = '235959'
                Write-Message -Message "Saturday End time was not set. Force is being used. Setting it to $SaturdayEndTime" -Level Verbose
            } elseif (-not $SaturdayEndTime) {
                Stop-Function -Message "Please enter a Saturday end time or use -Force to use defaults."
                return
            } elseif ($SaturdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Sunday', 'Weekends')) {
            # Check the start time
            if (-not $SundayStartTime -and $Force) {
                $SundayStartTime = '000000'
                Write-Message -Message "Sunday Start time was not set. Force is being used. Setting it to $SundayStartTime" -Level Verbose
            } elseif (-not $SundayStartTime) {
                Stop-Function -Message "Please enter a Sunday start time or use -Force to use defaults."
                return
            } elseif ($SundayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }

            # Check the end time
            if (-not $SundayEndTime -and $Force) {
                $SundayEndTime = '235959'
                Write-Message -Message "Sunday End time was not set. Force is being used. Setting it to $SundayEndTime" -Level Verbose
            } elseif (-not $SundayEndTime) {
                Stop-Function -Message "Please enter a Sunday End Time or use -Force to use defaults."
                return
            } elseif ($SundayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            # Check the start time
            if (-not $WeekdayStartTime -and $Force) {
                $WeekdayStartTime = '000000'
                Write-Message -Message "Weekday Start time was not set. Force is being used. Setting it to $WeekdayStartTime" -Level Verbose
            } elseif (-not $WeekdayStartTime) {
                Stop-Function -Message "Please enter Weekday Start Time or use -Force to use defaults."
                return
            } elseif ($WeekdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }

            # Check the end time
            if (-not $WeekdayEndTime -and $Force) {
                $WeekdayEndTime = '235959'
                Write-Message -Message "Weekday End time was not set. Force is being used. Setting it to $WeekdayEndTime" -Level Verbose
            } elseif (-not $WeekdayEndTime) {
                Stop-Function -Message "Please enter a Weekday End Time or use -Force to use defaults."
                return
            } elseif ($WeekdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'. Pager Day not set."
                return
            }
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod -notin ('NotifyEmail', 'NotifyPager'))) {
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

        foreach ($instance in $SqlInstance) {
            try {
                $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($server in $InputObject) {
            $failsafe = $server.JobServer.AlertSystem | Select-Object FailsafeOperator

            if ((Get-DbaAgentOperator -SqlInstance $server -Operator $Operator).Count -ne 0) {
                if ($force -eq $false) {
                    if ($Pscmdlet.ShouldProcess($server, "Operator $operator exists at $server. Use -Force to drop and and create it.")) {
                        Write-Message -Level Verbose -Message "Operator $operator exists at $server. Use -Force to drop and create."
                    }
                    continue
                } else {
                    if ($failsafe.FailsafeOperator -eq $operator -and $IsFailsafeOperator) {
                        Write-Message -Level Verbose -Message "$operator is the failsafe operator. Skipping drop."
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($server, "Dropping operator $operator")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping Operator $operator"
                            $server.JobServer.Operators[$operator].Drop()
                        } catch {
                            Stop-Function -Message "Issue dropping operator" -Category InvalidOperation -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server, "Creating Operator $operator")) {
                try {
                    $JobServer = $server.JobServer
                    $operators = $JobServer.Operators
                    $operators = New-Object Microsoft.SqlServer.Management.Smo.Agent.Operator( $JobServer, $Operator)

                    if ($EmailAddress) {
                        $operators.EmailAddress = $EmailAddress
                    }

                    if ($NetSendAddress) {
                        $operators.NetSendAddress = $NetSendAddress
                    }

                    if ($PagerAddress) {
                        $operators.PagerAddress = $PagerAddress
                    }

                    if ($Interval) {
                        $operators.PagerDays = $Interval
                    }

                    if ($SaturdayStartTime) {
                        $operators.SaturdayPagerStartTime = $SaturdayStartTime
                    }

                    if ($SaturdayEndTime) {
                        $operators.SaturdayPagerEndTime = $SaturdayEndTime
                    }

                    if ($SundayStartTime) {
                        $operators.SundayPagerStartTime = $SundayStartTime
                    }

                    if ($SundayEndTime) {
                        $operators.SundayPagerEndTime = $SundayEndTime
                    }

                    if ($WeekdayStartTime) {
                        $operators.WeekdayPagerStartTime = $WeekdayStartTime
                    }

                    if ($WeekdayEndTime) {
                        $operators.WeekdayPagerEndTime = $WeekdayEndTime
                    }

                    $operators.Create()

                    if ($IsFailsafeOperator) {
                        $server.JobServer.AlertSystem.FailSafeOperator = $Operator
                        $server.JobServer.AlertSystem.FailSafeOperator.NotificationMethod = $FailsafeNotificationMethod
                        $server.JobServer.AlertSystem.Alter()
                    }

                    Write-Message -Level Verbose -Message "Creating Operator $operator"
                    Get-DbaAgentOperator -SqlInstance $server -Operator $Operator
                } catch {
                    Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $server
                }
            }
        }
    }
}