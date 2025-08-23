function Install-DbaAgentAdminAlert {
    <#
    .SYNOPSIS
        Creates standard SQL Server Agent alerts for critical system errors and disk I/O failures

    .DESCRIPTION
        Creates a predefined set of SQL Server Agent alerts that monitor for critical system errors (severity levels 17-25) and disk I/O corruption errors (messages 823-825). These alerts catch serious issues like hardware failures, database corruption, insufficient resources, and fatal system errors that require immediate DBA attention.

        The function automatically creates alerts for severity levels 17-25 and error messages 823-825 unless specifically excluded. It can create missing operators and alert categories as needed, making it easy to establish consistent monitoring across multiple SQL Server instances.

        You can specify an operator to use for the alert, or it will use any operator it finds if there is just one. Alternatively, if you specify both an operator name and an email, it will create the operator if it does not exist.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeSeverity
        Exclude specific severities from the batch. By default, severities 17-25 are included.

    .PARAMETER ExcludeMessageId
        Exclude specific message IDs from the batch. By default, mesasage IDs 823-825 are included.

    .PARAMETER Operator
        The name of the operator to use in the alert

    .PARAMETER OperatorEmail
        If a the specified operator does not exist and an OperatorEmail is specified, the operator will be created

    .PARAMETER Category
        The name of the category for the alert. If not specified, the alert will be created in the 'Uncategorized' category.

        If the category does not exist, it will be created.

    .PARAMETER Database
        The name of the database to which the alert applies

    .PARAMETER DelayBetweenResponses
        The delay (in seconds) between responses to the alert

    .PARAMETER Disabled
        Whether the alert is disabled

    .PARAMETER NotifyMethod
        The method to use to notify the user of the alert. Valid values are 'None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll'. It is NotifyAll by default.

    .PARAMETER NotificationMessage
        The message to send when the alert is triggered

    .PARAMETER EventDescriptionKeyword
        The keyword to search for in the event description

    .PARAMETER JobId
        The GUID ID of the job to execute when the alert is triggered

    .PARAMETER EventSource
        The source of the event

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaAgentAdminAlert

    .EXAMPLE
        PS C:\> Install-DbaAgentAdminAlert -SqlInstance sql1

        Creates alerts for severity 17-25 and messages 823-825 on sql1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Category,
        [string]$Database,
        [string]$Operator,
        [string]$OperatorEmail,
        [int]$DelayBetweenResponses,
        [switch]$Disabled,
        [string]$EventDescriptionKeyword,
        [string]$EventSource,
        [string]$JobId = "00000000-0000-0000-0000-000000000000",
        [int[]]$ExcludeSeverity,
        [int[]]$ExcludeMessageId,
        [string]$NotificationMessage,
        [ValidateSet('None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll')]
        [string]$NotifyMethod = "NotifyAll",
        [switch]$EnableException
    )
    begin {
        $namehash = @{
            17  = 'Severity 017 - Insufficient Resources'
            18  = 'Severity 018 - Nonfatal Internal Error'
            19  = 'Severity 019 - SQL Server Error in Resource'
            20  = 'Severity 020 - SQL Server Fatal Error in Current Process'
            21  = 'Severity 021 - SQL Server Fatal Error in Database Process'
            22  = 'Severity 022 - Table Integrity Suspect'
            23  = 'Severity 023 - Database Integrity Suspect'
            24  = 'Severity 024 - Hardware Error'
            25  = 'Severity 025 - Fatal System Error'
            823 = 'Error Number 823 - Read/Write Error'
            824 = 'Error Number 824 - Read/Write Error'
            825 = 'Error Number 825 - Read/Write Error'
        }

        $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "Severity", "MessageId"

        if ($PSBoundParameters.JobId) {
            $defaults += "JobName"
        }

        if ($PSBoundParameters.Category) {
            $defaults += "CategoryName"
        }

        if ($PSBoundParameters.DelayBetweenResponses) {
            $defaults += "DelayBetweenResponses"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Operator) {
                try {
                    $newop = Get-DbaAgentOperator -SqlInstance $server -Operator $Operator
                    if (-not $newop -and $OperatorEmail) {
                        if ($PSCmdlet.ShouldProcess($instance, "Creating operator $Operator with email $OperatorEmail")) {
                            Write-Message -Level Verbose -Message "Creating operator $Operator with email $OperatorEmail on $instance"
                            $parms = @{
                                SqlInstance = $server
                                Operator    = $Operator
                                Email       = $OperatorEmail
                            }
                            $newop = New-DbaAgentOperator @parms
                            $null = $server.JobServer.Operators.Refresh()
                            $null = $server.JobServer.Refresh()

                            if (-not $newop) {
                                $parms = @{
                                    Message  = "Failed to create operator $Operator with email $OperatorEmail on $instance"
                                    Target   = $instance
                                    Continue = $true
                                }
                                Stop-Function @parms
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure" -Category OperatorError -ErrorRecord $PSItem -Target $instance -Continue
                }
            }

            if ($Category) {
                try {
                    $newcat = Get-DbaAgentAlertCategory -SqlInstance $server -Category $Category
                    if (-not $newcat) {
                        if ($PSCmdlet.ShouldProcess($instance, "Creating alert category $Category")) {
                            Write-Message -Level Verbose -Message "Creating alert category $Category on $instance"
                            $parms = @{
                                SqlInstance = $server
                                Category    = $Category
                            }
                            $newcat = New-DbaAgentAlertCategory @parms

                            if (-not $newcat) {
                                $parms = @{
                                    Message  = "Failed to create category $Category on $instance"
                                    Target   = $instance
                                    Continue = $true
                                }
                                Stop-Function @parms
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure" -Category OperatorError -ErrorRecord $PSItem -Target $instance -Continue
                }
            }

            if (-not $PSBoundParameters.Operator) {
                if ($PSCmdlet.ShouldProcess($instance, "Checking for operator $Operator")) {
                    $newop = Get-DbaAgentOperator -SqlInstance $server
                    if ($newop.Count -gt 1) {
                        Stop-Function -Message "More than one operator found on $instance and operator not specified" -Target $instance -Continue
                    }

                    if ($newop.Count -eq 0) {
                        Stop-Function -Message "No operator found on $instance and operator not specified. You can create a new operator using the Operator and OperatorEmail parameters." -Target $instance -Continue
                    }
                }
                $Operator = $newop.Name
            }

            $parms = @{
                SqlInstance  = $server
                Alert        = $name
                Disabled     = $Disabled
                NotifyMethod = $NotifyMethod
            }

            if ($DelayBetweenResponses -gt 0) {
                $null = $parms.Add("DelayBetweenResponses", $DelayBetweenResponses)
            }

            if ($Database) {
                $null = $parms.Add("Database", $Database)
            }

            if ($EventDescriptionKeyword) {
                $null = $parms.Add("EventDescriptionKeyword", $EventDescriptionKeyword)
            }

            if ($EventSource) {
                $null = $parms.Add("EventSource", $EventSource)
            }

            if ($JobId) {
                $null = $parms.Add("JobId", $JobId)
            }

            if ($NotificationMessage) {
                $null = $parms.Add("NotificationMessage", $NotificationMessage)
            }

            if ($Operator) {
                $null = $parms.Add("Operator", $Operator)
            }

            if ($Category) {
                $null = $parms.Add("Category", $Category)
            }

            if ($ExcludeSeverity) {
                foreach ($number in $ExcludeSeverity) {
                    $null = $namehash.Remove($number)
                }
            }

            if ($ExcludeMessageId) {
                foreach ($number in $ExcludeMessageId) {
                    $null = $namehash.Remove($number)
                }
            }

            foreach ($item in $namehash.Keys) {
                $name = $namehash[$item]
                $parms.Alert = $name
                $parms.Severity = 0
                $parms.MessageId = 0

                if ($item -lt 823) {
                    $parms.Severity = $item
                } else {
                    $parms.MessageId = $item
                }

                if ($name -in $server.JobServer.Alerts.Name) {
                    Stop-Function -Message "Alert '$name' already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the alert $name")) {
                        try {
                            # Supply either a non-zero message ID, non-zero severity, non-null performance condition, or non-null WMI namespace and query.
                            $null = New-DbaAgentAlert @parms -EnableException
                        } catch {
                            Stop-Function -Message "Something went wrong creating the alert $name on $instance" -Target $name -Continue -ErrorRecord $_
                        }
                    }
                }
                Get-DbaAgentAlert -SqlInstance $server -Alert $name | Select-DefaultView -Property $defaults
            }
        }
    }
}