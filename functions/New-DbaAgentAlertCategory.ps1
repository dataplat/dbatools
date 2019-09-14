function New-DbaAgentAlertCategory {
    <#
    .SYNOPSIS
        New-DbaAgentAlertCategory creates a new alert category.

    .DESCRIPTION
        New-DbaAgentAlertCategory makes it possible to create a Agent Alert category that can be used with Alerts.
        It returns an array of the alert categories created .

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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