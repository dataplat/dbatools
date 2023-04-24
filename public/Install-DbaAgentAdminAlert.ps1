function Install-DbaAgentAdminAlert {
    <#
    .SYNOPSIS
        Creates SQL Server Agent alerts commonly needed by DBAs

    .DESCRIPTION
        Creates SQL Server Agent alerts commonly needed by DBAs

        You can specify an operator to use for the alert, or it will use any operator it finds if there is just one.

        Alternatively, if you specify both an operator name and an email, it will create the operator if it does not exist.

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
        PS C:\> Install-DbaAgentAdminAlert -SqlInstance sql1 -Alert "Severity 018 - Nonfatal Internal Error"

        Creates a new alert with the name Severity 018 - Nonfatal Internal Error.

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
    process {
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
                            Stop-Function -Message "Something went wrong creating the alert $name on $instance" -Target $name -Continue -ErrorRecord $_
                        }
                    }
                }
                Get-DbaAgentAlert -SqlInstance $server -Alert $name
            }
        }
    }
}