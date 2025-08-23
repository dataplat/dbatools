function New-DbaAgentAlertCategory {
    <#
    .SYNOPSIS
        Creates new SQL Agent alert categories for organizing and managing database alerts.

    .DESCRIPTION
        Creates custom alert categories in SQL Server Agent to help organize and group related alerts for better management and monitoring.
        Alert categories allow DBAs to logically group alerts by function, severity, or responsibility, making it easier to assign different categories to different teams or escalation procedures.
        This is particularly useful in environments with many alerts where categorization helps with organization, reporting, and maintenance workflows.
        Returns the newly created alert category objects that can be immediately used when configuring SQL Agent alerts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert, AlertCategory
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAgentAlertCategory

    .EXAMPLE
        PS C:\> New-DbaAgentAlertCategory -SqlInstance sql1 -Category 'Category 1'

        Creates a new alert category with the name 'Category 1'.

    .EXAMPLE
        PS C:\>'sql1' | New-DbaAgentAlertCategory -Category 'Category 2'

        Creates a new alert category with the name 'Category 2'.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cat in $Category) {
                if ($cat -in $server.JobServer.AlertCategories.Name) {
                    Stop-Function -Message "Alert category $cat already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the alert category $cat")) {
                        try {
                            $alertCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory($server.JobServer, $cat)

                            $alertCategory.Create()

                            $server.JobServer.Refresh()
                        } catch {
                            Stop-Function -Message "Something went wrong creating the alert category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                        }
                    }
                }
                Get-DbaAgentAlertCategory -SqlInstance $server -Category $cat
            }
        }
    }
}