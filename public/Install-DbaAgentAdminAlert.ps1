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
        Excludes specific error severity levels from the standard alert creation. By default, the function creates alerts for severity levels 17-25 which cover resource issues, internal errors, and fatal system problems.
        Use this when you want to skip certain severities, perhaps because you already have custom alerts configured for them or they're not relevant to your environment.

    .PARAMETER ExcludeMessageId
        Excludes specific SQL Server error message IDs from the standard alert creation. By default, the function creates alerts for messages 823-825 which detect disk I/O hardware errors and database corruption issues.
        Use this when you want to skip certain message IDs, perhaps because you have existing custom alerts for these errors or they don't apply to your storage configuration.

    .PARAMETER Operator
        Specifies the SQL Server Agent operator who will receive notifications when these alerts are triggered. The operator must already exist on the target instance unless you also provide OperatorEmail.
        If not specified and only one operator exists on the instance, that operator will be used automatically. Required for alert notifications to function properly.

    .PARAMETER OperatorEmail
        Creates a new SQL Server Agent operator with this email address if the specified operator name doesn't exist. Must be used together with the Operator parameter.
        This allows you to set up both the operator and alerts in a single command when configuring monitoring on a new instance.

    .PARAMETER Category
        Assigns the alerts to a specific SQL Server Agent alert category for better organization and management. Defaults to 'Uncategorized' if not specified.
        Use this to group related alerts together, making it easier to manage alert policies and review alert activity in SQL Server Management Studio. If the category doesn't exist, it will be created automatically.

    .PARAMETER Database
        Restricts the alerts to fire only for errors occurring in the specified database. If not specified, alerts will fire for errors in any database on the instance.
        Use this when you want to monitor only specific critical databases and avoid noise from test or development databases on the same instance.

    .PARAMETER DelayBetweenResponses
        Sets the minimum time in seconds that must pass before the alert can fire again for the same condition. Prevents notification spam when errors occur repeatedly.
        Use this to avoid flooding your inbox during cascading failures or when the same error occurs multiple times in rapid succession.

    .PARAMETER Disabled
        Creates the alerts in a disabled state, preventing them from firing until manually enabled. By default, alerts are created in an enabled state.
        Use this when you want to set up the alert infrastructure first and enable specific alerts later after testing or validation.

    .PARAMETER NotifyMethod
        Specifies how the operator should be notified when the alert fires. Valid options are 'NotifyEmail', 'Pager', 'NetSend', 'NotifyAll', or 'None'. Defaults to 'NotifyAll'.
        Use 'NotifyEmail' for email-only notifications, 'NotifyAll' to use all configured notification methods for the operator, or 'None' to create alerts without notifications (useful for logging only).

    .PARAMETER NotificationMessage
        Customizes the message content sent to operators when an alert fires. If not specified, SQL Server uses the default system-generated message.
        Use this to include specific instructions, contact information, or troubleshooting steps that help your team respond more effectively to critical errors.

    .PARAMETER EventDescriptionKeyword
        Filters alerts to fire only when the error message text contains this specific keyword or phrase. Applied in addition to the standard severity and message ID criteria.
        Use this to create more targeted alerts that focus on specific error conditions within the broader categories of critical system errors.

    .PARAMETER JobId
        Specifies a SQL Server Agent job to execute automatically when any of these alerts fire. Must be a valid job GUID that exists on the target instance.
        Use this to trigger automated response scripts, such as collecting diagnostic information, attempting automatic recovery, or escalating to additional monitoring systems.

    .PARAMETER EventSource
        Restricts alerts to fire only for errors originating from a specific event source or application. If not specified, alerts will fire regardless of the error source.
        Use this to focus monitoring on specific applications or services that interact with your SQL Server instance when you want to isolate alerts from particular systems.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Alert

        Returns one Alert object per severity level or message ID for which an alert was successfully created. By default, this results in 12 objects (9 severity levels 17-25 plus 3 message IDs 823-825), or fewer if specific severities or message IDs are excluded via -ExcludeSeverity or -ExcludeMessageId parameters.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - InstanceName: The SQL Server instance name
        - Name: The alert name (e.g., "Severity 017 - Insufficient Resources", "Error Number 823 - Read/Write Error")
        - Severity: The error severity level being monitored (0 for message ID alerts, 17-25 for severity alerts)
        - MessageId: The error message ID being monitored (0 for severity alerts, 823-825 for message ID alerts)

        Conditional default display properties (added when corresponding parameter is specified):
        - JobName: Name of the SQL Server Agent job executed when alert fires (added when -JobId is specified)
        - CategoryName: Name of the alert category (added when -Category is specified)
        - DelayBetweenResponses: Minimum seconds between alert notifications (added when -DelayBetweenResponses is specified)

        Additional properties available (from SMO Alert object):
        - ID: Unique identifier for the alert within the instance
        - AlertType: Type of alert (Severity or Message ID based)
        - IsEnabled: Boolean indicating if the alert is enabled
        - LastRaised: DateTime when the alert last fired
        - OccurrenceCount: Number of times the alert has fired
        - CategoryId: Numeric identifier of the alert category
        - CreateDate: DateTime when the alert was created
        - DateLastModified: DateTime when the alert was last modified
        - DatabaseName: Name of specific database alert is restricted to (if -Database was specified)
        - Urn: The Uniform Resource Name of the alert object
        - State: SMO object state (Existing, Creating, Pending, Dropping, etc.)
        - Notifications: DataTable containing notification settings for operators
        - EventSource: Event source filter if specified
        - EventDescriptionKeyword: Event description keyword filter if specified
        - NotifyMethod: Notification method configured for the alert

        All properties from the base SMO Alert object are accessible using Select-Object * even though only default properties are displayed by default.

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