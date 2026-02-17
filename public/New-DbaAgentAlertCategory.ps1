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
        Specifies the name or names of the alert categories to create in SQL Server Agent.
        Use descriptive names that reflect how you organize alerts, such as 'Database Errors', 'Performance Issues', or 'Security Events'.
        Multiple categories can be created in a single operation by providing an array of category names.

    .PARAMETER Force
        Bypasses confirmation prompts and creates the alert categories without user interaction.
        Use this parameter in automated scripts or when you're confident about the category names being created.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.AlertCategory

        Returns one AlertCategory object for each category created. The returned objects represent the newly created alert categories and are fully functional for immediate assignment to SQL Agent alerts.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the alert category
        - ID: Unique identifier for the alert category within the instance
        - AlertCount: The number of alerts currently assigned to this category (integer)

        All properties from the base SMO AlertCategory object are accessible using Select-Object *.

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
                            try {
                                $alertCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory($server.JobServer, $cat)
                            } catch {
                                if ($_.Exception.Message -match "newParent") {
                                    Stop-Function -Message "Cannot create agent alert category through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $cat -Continue
                                    return
                                } else {
                                    throw
                                }
                            }

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