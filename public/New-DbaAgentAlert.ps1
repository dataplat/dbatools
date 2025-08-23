function New-DbaAgentAlert {
    <#
    .SYNOPSIS
        Creates SQL Server Agent alerts for automated monitoring and notification of errors, performance conditions, or system events

    .DESCRIPTION
        Creates new SQL Server Agent alerts that monitor for specific error severities, message IDs, performance conditions, or WMI events. Alerts can automatically notify operators via email, pager, or net send when triggered, and optionally execute jobs in response to the monitored condition. Supports configurable notification delays to prevent alert spam and can target specific databases or system-wide monitoring scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Alert
        Specifies the name for the new SQL Server Agent alert. Must be unique within the SQL Server instance.
        Use descriptive names that clearly identify the alert's purpose, such as 'High Severity Errors' or 'Database Full'.

    .PARAMETER Category
        Assigns the alert to a specific category for organization and management purposes.
        Categories help group related alerts together in SQL Server Management Studio and can be used for filtering in reports.

    .PARAMETER Database
        Restricts the alert to monitor events occurring only in the specified database.
        Leave blank to monitor all databases on the instance, or specify a database name to limit scope and reduce false positives.

    .PARAMETER DelayBetweenResponses
        Sets the minimum time in seconds between alert notifications to prevent notification spam.
        Use higher values like 300-900 seconds for recurring issues to avoid overwhelming operators with repeated alerts.

    .PARAMETER Disabled
        Creates the alert in a disabled state, preventing it from triggering until manually enabled.
        Useful when setting up alerts during maintenance windows or when you need to configure notifications before activating monitoring.

    .PARAMETER EventDescriptionKeyword
        Filters alert triggers to only events containing this keyword in the error message text.
        Use this to create targeted alerts for specific error conditions like 'deadlock', 'timeout', or 'corruption' within broader error categories.

    .PARAMETER NotifyMethod
        The method to use to notify the user of the alert. Valid values are 'None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll'. It is NotifyAll by default.

        The Pager and net send options will be removed from SQL Server Agent in a future version of Microsoft SQL Server.

        Avoid using these features in new development work, and plan to modify applications that currently use these features.

    .PARAMETER Operator
        Specifies which SQL Server Agent operators will receive notifications when this alert fires.
        The operators must already exist and be configured with valid email addresses, pager numbers, or net send addresses.

    .PARAMETER EventSource
        Identifies the source application or component for WMI event monitoring.
        Required when creating WMI-based alerts to specify which system component's events should trigger the alert.

    .PARAMETER JobId
        Specifies the GUID of a SQL Server Agent job to automatically execute when the alert fires.
        Use this for automated responses like running diagnostics, performing cleanup, or triggering failover procedures.

    .PARAMETER MessageId
        Creates an alert that triggers on a specific SQL Server error message number.
        Use this for precise monitoring of known error conditions like message 9002 (transaction log full) or 825 (read-retry errors).

    .PARAMETER NotificationMessage
        Defines custom text to include in alert notifications sent to operators.
        Use this to provide context, troubleshooting steps, or escalation procedures specific to this alert condition.

    .PARAMETER PerformanceCondition
        Defines a performance counter condition that triggers the alert when threshold values are exceeded.
        Specify conditions like 'SQLServer:General Statistics|Logins/sec|>|100' to monitor performance metrics and respond to resource issues.

    .PARAMETER Severity
        Sets the SQL Server error severity level that triggers this alert, ranging from 0-25.
        Common values include 16-18 for user errors, 19-21 for resource issues, and 22-25 for system errors requiring immediate attention.

    .PARAMETER WmiEventNamespace
        Specifies the WMI namespace to monitor for events, typically 'root\cimv2' for system events.
        Required when creating WMI-based alerts to monitor Windows system events, hardware failures, or application-specific WMI providers.

    .PARAMETER WmiEventQuery
        Defines the WQL (WMI Query Language) query that determines which WMI events trigger the alert.
        Use queries like 'SELECT * FROM Win32_VolumeChangeEvent' to monitor specific system events outside of SQL Server's direct control.

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
        https://dbatools.io/New-DbaAgentAlert

    .EXAMPLE
        PS C:\> $parms = @{
                SqlInstance           = "sql01"
                Severity              = 18
                Alert                 = "Severity 018 - Nonfatal Internal Error"
                DelayBetweenResponses = 60
                NotifyMethod          = "NotifyEmail"
            }

        PS C:\> $alert = New-DbaAgentAlert @parms

        Creates a new alert for severity 18 with the name Severity 018 - Nonfatal Internal Error.

        It will send an email to the default operator and wait 60 seconds before sending another email.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Alert,
        [string]$Category,
        [string]$Database,
        [string[]]$Operator,
        [int]$DelayBetweenResponses = 60,
        [switch]$Disabled,
        [string]$EventDescriptionKeyword,
        [string]$EventSource,
        [string]$JobId = "00000000-0000-0000-0000-000000000000",
        [int]$Severity,
        [int]$MessageId,
        [string]$NotificationMessage,
        [string]$PerformanceCondition,
        [string]$WmiEventNamespace,
        [string]$WmiEventQuery,
        [ValidateSet('None', 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll')]
        [string]$NotifyMethod = "NotifyAll",
        [switch]$EnableException
    )
    process {
        if ($NotifyMethod) {
            $null = Set-Variable -Name IncludeEventDescription -Value $NotifyMethod
        }

        if ($Category) {
            $null = Set-Variable -Name CategoryName -Value $Category
        }

        if ($Database) {
            $null = Set-Variable -Name DatabaseName -Value $Database
        }

        if ($MessageId -gt 0 -and -not $Severity) {
            $Severity = 0
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($name in $Alert) {
                if ($name -in $server.JobServer.Alerts.Name) {
                    Stop-Function -Message "Alert '$name' already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the alert $name")) {
                        try {
                            # Supply either a non-zero message ID, non-zero severity, non-null performance condition, or non-null WMI namespace and query.
                            $newalert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($server.JobServer, $name)
                            $list = "CategoryName", "DatabaseName", "DelayBetweenResponses", "EventDescriptionKeyword", "EventSource", "JobID", "MessageID", "NotificationMessage", "PerformanceCondition", "WmiEventNamespace", "WmiEventQuery", "IncludeEventDescription", "IsEnabled", "Severity"

                            foreach ($item in $list) {
                                $value = (Get-Variable -Name $item -ErrorAction Ignore).Value

                                if ($value) {
                                    $newalert.$item = $value
                                }
                            }

                            $newalert.Create()

                            if ($Operator -and $NotifyMethod) {
                                foreach ($op in $Operator) {
                                    try {
                                        Write-Message -Level Verbose -Message "Adding notification of type $NotifyMethod for $op to $instance"
                                        $newalert.AddNotification($op, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::$NotifyMethod)
                                        $newalert.Alter()
                                    } catch {
                                        Stop-Function -Message "Error adding notification of type $NotifyMethod for $op to $instance" -Target $name -Continue -ErrorRecord $_
                                    }
                                }
                            }
                            $null = $server.JobServer.Refresh()
                        } catch {
                            Stop-Function -Message "Something went wrong creating the alert $name on $instance" -Target $name -Continue -ErrorRecord $PSItem
                        }
                    }
                }
                Get-DbaAgentAlert -SqlInstance $server -Alert $name
            }
        }
    }
}