function Set-DbaAgentOperator {
    <#
    .SYNOPSIS
        Modifies existing SQL Agent operator contact details, pager schedules, and failsafe settings.

    .DESCRIPTION
        Modifies existing SQL Agent operators by updating their contact information, pager notification schedules, and failsafe operator configuration. This lets you change email addresses, pager contacts, net send addresses, and specify when pager notifications should be active without having to manually update operators through SQL Server Management Studio. You can also designate an operator as the failsafe operator that receives notifications when the primary assigned operators are unavailable.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        Name of the operator in SQL Agent.

    .PARAMETER Name
        The new name of the agent operator.

    .PARAMETER EmailAddress
        The email address the SQL Agent will use to email alerts to the operator.

    .PARAMETER NetSendAddress
        The net send address the SQL Agent will use for the operator to net send alerts.

    .PARAMETER PagerAddress
        The pager email address the SQL Agent will use to send alerts to the operator.

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
        Defines the notification method(s) for the failsafe operator. The default is 'NotifyEmail'.
        Valid parameter values are 'None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll'.
        Values 'NotifyEmail', 'Pager', 'NetSend' can be specified in any combination.
        Values 'None' and 'NotifyAll' cannot be specified in conjunction with any other value.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentOperator

    .EXAMPLE
        PS C:\> Set-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com -PagerDay Everyday

        This sets the operator named DBA with the above email address with default values to alerts everyday for all hours of the day.

    .EXAMPLE
        PS C:\> Set-DbaAgentOperator -SqlInstance sql01 -Operator DBA -EmailAddress operator@operator.com `
        >>  -NetSendAddress dbauser1 -PagerAddress dbauser1@pager.dbatools.io -PagerDay Everyday `
        >>  -SaturdayStartTime 070000 -SaturdayEndTime 180000 -SundayStartTime 080000 `
        >>  -SundayEndTime 170000 -WeekdayStartTime 060000 -WeekdayEndTime 190000

        Creates a new operator named DBA on the sql01 instance with email address operator@operator.com, net send address of dbauser1, pager address of dbauser1@pager.dbatools.io, page day as every day, Saturday start time of 7am, Saturday end time of 6pm, Sunday start time of 8am, Sunday end time of 5pm, Weekday start time of 6am, and Weekday end time of 7pm.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Operator,
        [string]$Name,
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
        [switch]$IsFailsafeOperator,
        [ValidateSet('None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll')]
        [string[]]$FailsafeNotificationMethod = 'NotifyEmail',
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Operator[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $PSBoundParameters.EmailAddress -and -not $PSBoundParameters.NetSendAddress -and -not $PSBoundParameters.PagerAddress) {
            Stop-Function -Message "You must specify either an EmailAddress, NetSendAddress, or a PagerAddress to be able to create an operator."
            return
        }

        if (-not $PSBoundParameters.InputObject -and -not $PSBoundParameters.Operator) {
            Stop-Function -Message "You must specify either operator or pipe in a list of operators"
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
            if (-not $SaturdayStartTime) {
                $SaturdayStartTime = '000000'
                Write-Message -Message "Saturday Start time was not set. Setting it to $SaturdayStartTime" -Level Verbose
            } elseif ($SaturdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SaturdayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $SaturdayEndTime) {
                $SaturdayEndTime = '235959'
                Write-Message -Message "Saturday End time was not set. Setting it to $SaturdayEndTime" -Level Verbose
            } elseif ($SaturdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "End time $SaturdayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Sunday', 'Weekends')) {
            # Check the start time
            if (-not $SundayStartTime) {
                $SundayStartTime = '000000'
                Write-Message -Message "Sunday Start time was not set. Setting it to $SundayStartTime" -Level Verbose
            } elseif ($SundayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Start time $SundayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $SundayEndTime) {
                $SundayEndTime = '235959'
                Write-Message -Message "Sunday End time was not set. Setting it to $SundayEndTime" -Level Verbose
            } elseif ($SundayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Sunday End time $SundayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($PagerDay -in ('Everyday', 'Weekdays', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
            # Check the start time
            if (-not $WeekdayStartTime) {
                $WeekdayStartTime = '000000'
                Write-Message -Message "Weekday Start time was not set. Setting it to $WeekdayStartTime" -Level Verbose
            } elseif ($WeekdayStartTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday Start time $WeekdayStartTime needs to match between '000000' and '235959'"
                return
            }

            # Check the end time
            if (-not $WeekdayEndTime) {
                $WeekdayEndTime = '235959'
                Write-Message -Message "Weekday End time was not set. Setting it to $WeekdayEndTime" -Level Verbose
            } elseif ($WeekdayEndTime -notmatch $RegexTime) {
                Stop-Function -Message "Weekday End time $WeekdayEndTime needs to match between '000000' and '235959'"
                return
            }
        }

        if ($IsFailsafeOperator -and ($FailsafeNotificationMethod.Count -gt 1 -and ($FailsafeNotificationMethod.Contains('None') -or $FailsafeNotificationMethod.Contains('NotifyAll')))) {
            Stop-Function -Message "The failsafe operator notification methods 'None' and 'NotifyAll' cannot be specified in conjunction with any other notification method."
            return
        } else {

            [int]$failsafeNotificationMethodEnumerated = 0

            if ($FailsafeNotificationMethod.Contains('NotifyAll')) {
                $failsafeNotificationMethodEnumerated += 7
            } else {

                if ($FailsafeNotificationMethod.Contains('NotifyEmail')) {
                    $failsafeNotificationMethodEnumerated += 1
                }

                if ($FailsafeNotificationMethod.Contains('Pager')) {
                    $failsafeNotificationMethodEnumerated += 2
                }

                if ($FailsafeNotificationMethod.Contains('NetSend')) {
                    $failsafeNotificationMethodEnumerated += 4
                }
            }

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

        if ($SqlInstance) {
            try {
                $InputObject += Get-DbaAgentOperator -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Operator $Operator -EnableException
            } catch {
                Stop-Function -Message "Failed" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }

        foreach ($op in $InputObject) {
            $server = $op | Get-ConnectionParent
            try {
                if ($Name) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) Name to $Name")) {
                        # instead of using .Rename(), we will execute a sql script to avoid enumeration problems when piping
                        $sql = "EXEC msdb.dbo.sp_update_operator @name=N'$($op.Name)', @new_name=N'$Name'"
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Query "$sql" -EnableException
                        } catch {
                            Stop-Function -Message "Failed on $($server.name)" -ErrorRecord $_ -Target $server -Continue
                        }
                        $server.JobServer.Operators.Refresh()
                        $op = Get-DbaAgentOperator -SqlInstance $server -Operator $Name
                    }
                }

                if ($EmailAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) EmailAddress to $EmailAddress")) {
                        $op.EmailAddress = $EmailAddress
                    }
                }

                if ($NetSendAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) NetSendAddress to $NetSendAddress")) {
                        $op.NetSendAddress = $NetSendAddress
                    }
                }

                if ($PagerAddress) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerAddress to $PagerAddress")) {
                        $op.PagerAddress = $PagerAddress
                    }
                }

                if ($Interval) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) PagerDays to $Interval")) {
                        $op.PagerDays = $Interval
                    }
                }

                if ($SaturdayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerStartTime to $SaturdayStartTime")) {
                        $op.SaturdayPagerStartTime = $SaturdayStartTime
                    }
                }

                if ($SaturdayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SaturdayPagerEndTime to $SaturdayEndTime")) {
                        $op.SaturdayPagerEndTime = $SaturdayEndTime
                    }
                }

                if ($SundayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerStartTime to $SundayStartTime")) {
                        $op.SundayPagerStartTime = $SundayStartTime
                    }
                }

                if ($SundayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) SundayPagerEndTime to $SundayEndTime")) {
                        $op.SundayPagerEndTime = $SundayEndTime
                    }
                }

                if ($WeekdayStartTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerStartTime to $WeekdayStartTime")) {
                        $op.WeekdayPagerStartTime = $WeekdayStartTime
                    }
                }

                if ($WeekdayEndTime) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating Operator $($op.Name) WeekdayPagerEndTime to $WeekdayEndTime")) {
                        $op.WeekdayPagerEndTime = $WeekdayEndTime
                    }
                }

                if ($IsFailsafeOperator) {
                    if ($Pscmdlet.ShouldProcess($server, "Updating FailSafe Operator to $operator")) {
                        $server.JobServer.AlertSystem.FailSafeOperator = $Operator
                        $server.JobServer.AlertSystem.NotificationMethod = $failsafeNotificationMethodEnumerated
                        $server.JobServer.AlertSystem.Alter()
                    }
                }

                if ($Pscmdlet.ShouldProcess($server, "Committing changes for Operator $($op.Name)")) {
                    $op.Alter()
                    $op
                }
            } catch {
                Stop-Function -Message "Issue creating operator." -Category InvalidOperation -ErrorRecord $_ -Target $server
            }
        }
    }
}