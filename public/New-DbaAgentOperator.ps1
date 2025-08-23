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
        Name of the SQL Server Agent operator to create. This becomes the operator name that shows up in SSMS and can be referenced by alerts and jobs for notifications.
        Use descriptive names like 'DBA Team' or 'On-Call Admin' to identify who receives notifications.

    .PARAMETER EmailAddress
        Email address where SQL Server Agent sends alert notifications and job failure notifications. This is the primary notification method for most operators.
        Specify a monitored email address or distribution list that reaches the appropriate support staff.

    .PARAMETER NetSendAddress
        Network address for receiving net send messages from SQL Server Agent. This is a legacy Windows messaging system rarely used in modern environments.
        Most organizations use email notifications instead since net send requires specific network configurations and may not work across subnets.

    .PARAMETER PagerAddress
        Email address for pager notifications, typically used for SMS gateways or mobile alerts. This works with email-to-SMS services provided by cellular carriers.
        Configure pager schedules with PagerDay and time parameters to control when these urgent notifications are sent.

    .PARAMETER PagerDay
        Controls which days pager notifications are active for this operator. Use this to match on-call schedules or business hours when immediate alerts are needed.
        Choose 'Weekdays' for business-hour coverage, 'EveryDay' for 24/7 support, or specific days like 'Monday' through 'Sunday' for rotation schedules.

    .PARAMETER SaturdayStartTime
        Starting time for Saturday pager notifications in HHMMSS format (e.g., '080000' for 8:00 AM). Required when PagerDay includes Saturday, Weekend, or EveryDay.
        Use '000000' for midnight start times or specify business hours to limit when urgent alerts are sent.

    .PARAMETER SaturdayEndTime
        Ending time for Saturday pager notifications in HHMMSS format (e.g., '180000' for 6:00 PM). Must be specified with SaturdayStartTime.
        Use '235959' for end-of-day coverage or match your organization's Saturday support hours.

    .PARAMETER SundayStartTime
        Starting time for Sunday pager notifications in HHMMSS format (e.g., '090000' for 9:00 AM). Required when PagerDay includes Sunday, Weekend, or EveryDay.
        Configure based on your weekend support schedule or emergency-only coverage requirements.

    .PARAMETER SundayEndTime
        Ending time for Sunday pager notifications in HHMMSS format (e.g., '170000' for 5:00 PM). Must be specified with SundayStartTime.
        Set to match your organization's weekend support availability or use '235959' for full-day coverage.

    .PARAMETER WeekdayStartTime
        Starting time for weekday pager notifications in HHMMSS format (e.g., '060000' for 6:00 AM). Required when PagerDay includes Weekdays or individual weekdays.
        Typically set to business hours start time or earlier for critical production monitoring.

    .PARAMETER WeekdayEndTime
        Ending time for weekday pager notifications in HHMMSS format (e.g., '190000' for 7:00 PM). Must be specified with WeekdayStartTime.
        Configure to match business hours end time or extend for after-hours support coverage.

    .PARAMETER IsFailsafeOperator
        Designates this operator as the failsafe operator for the SQL Server instance. The failsafe operator receives notifications when all other operators are unavailable.
        Only one failsafe operator can exist per instance, and this setting replaces any existing failsafe operator configuration.

    .PARAMETER FailsafeNotificationMethod
        Specifies how the failsafe operator receives notifications when used with IsFailsafeOperator. Choose 'NotifyEmail' for email notifications or 'NotifyPager' for pager alerts.
        Defaults to 'NotifyEmail' which works with most modern notification systems and email-to-SMS gateways.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Drops and recreates the operator if it already exists on the target instance. Without this switch, the function will skip existing operators to prevent accidental overwrites.
        Use this when updating operator configurations or when you need to ensure consistent settings across multiple environments.

    .PARAMETER InputObject
        Accepts SQL Server Management Objects (SMO) server instances from Connect-DbaInstance via pipeline. This allows you to create operators on pre-authenticated server connections.
        Use this when you have existing server connections or need to process multiple instances with specific connection properties.

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