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
        PS C:\> Install-DbaAgentAdminAlert -SqlInstance sql1 -Alert "Severity 018 - Nonfatal Internal Error"

        Creates a new alert with the name Severity 018 - Nonfatal Internal Error.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
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
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Operator) {
                $newop = Get-DbaOperator -SqlInstance $server
                if (-not $newop -and $OperatorEmail) {
                    Write-Message -Level Verbose -Message "Creating operator $Operator with email $OperatorEmail on $instance"
                    $parms = @{
                        SqlInstance = $server
                        Operator    = $Operator
                        Email       = $OperatorEmail
                    }
                    $newop = New-DbaOperator @parms

                    if (-not $newop) {
                        Stop-Function -Message "Failed to create operator $Operator with email $OperatorEmail on $instance" -Target $instance -Continue
                    }
                }
            }

            if (-not $Operator) {
                $newop = Get-DbaOperator -SqlInstance $server
                if ($newop.Count -gt 1) {
                    Stop-Function -Message "More than one operator found on $instance and operator not specified" -Target $instance -Continue
                }

                if ($newop.Count -eq 0) {
                    Stop-Function -Message "No operator found on $instance and operator not specified. You can create a new operator using the Operator and OperatorEmail parameters." -Target $instance -Continue
                }
            }

            $parms = @{
                SqlInstance             = $server
                Name                    = $name
                Database                = $Database
                DelayBetweenResponses   = $DelayBetweenResponses
                Disabled                = $Disabled
                EventDescriptionKeyword = $EventDescriptionKeyword
                EventSource             = $EventSource
                JobId                   = $JobId
                ExcludeSeverity         = $ExcludeSeverity
                ExcludeMessageId        = $ExcludeMessageId
                NotificationMessage     = $NotificationMessage
                NotifyMethod            = $NotifyMethod
                Operator                = $Operator
                Category                = $Category
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

            foreach ($item in $namehash) {
                $name = $item.Value
                $parms.Name = $name
                $parms.Severity = 0
                $parms.MessageId = 0

                if ($item.Key -lt 823) {
                    $parms.Severity = $item.Key
                } else {
                    $parms.MessageId = $item.Key
                }

                if ($name -in $server.JobServer.Alerts.Name) {
                    Stop-Function -Message "Alert '$name' already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the alert $name")) {
                        try {
                            # Supply either a non-zero message ID, non-zero severity, non-null performance condition, or non-null WMI namespace and query.
                            New-DbaAgentAlert @parms
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