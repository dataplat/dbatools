function Set-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Set-DbaAgentJobCategory changes a job category.

    .DESCRIPTION
        Set-DbaAgentJobCategory makes it possible to change a job category.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category

    .PARAMETER NewName
        New name of the job category

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
        Tags: Agent, Job, JobCategory
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1' -NewName 'Category 2'

        Change the name of the category from 'Category 1' to 'Category 2'.

    .EXAMPLE
        PS C:\> Set-DbaAgentJobCategory -SqlInstance sql1, sql2 -Category Category1, Category2 -NewName cat1, cat2

        Rename multiple jobs in one go on multiple servers.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [string[]]$NewName,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check if multiple categories are being changed
        if ($Category.Count -gt 1 -and $NewName.Count -eq 1) {
            Stop-Function -Message "You cannot rename multiple jobs to the same name" -Target $instance
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Loop through each of the categories
            foreach ($cat in $Category) {
                # Check if the category exists
                if ($cat -notin $server.JobServer.JobCategories.Name) {
                    Stop-Function -Message "Job category $cat doesn't exist on $instance" -Target $instance -Continue
                }

                # Check if the category already exists
                if ($NewName -and ($NewName -in $server.JobServer.JobCategories.Name)) {
                    Stop-Function -Message "Job category $NewName already exists on $instance" -Target $instance -Continue
                }

                if ($PSCmdlet.ShouldProcess($instance, "Changing the job category $Category")) {
                    try {
                        # Get the job category object
                        $currentCategory = $server.JobServer.JobCategories[$cat]

                        Write-Message -Message "Changing job category $cat" -Level Verbose

                        # Get and set the original and new values
                        $newCategoryName = $null

                        # Check if the job category needs to be renamed
                        if ($NewName) {
                            $currentCategory.Rename($NewName[$Category.IndexOf($cat)])
                            $newCategoryName = $currentCategory.Name
                        }

                        Get-DbaAgentJobCategory -SqlInstance $server -Category $newCategoryName
                    } catch {
                        Stop-Function -Message "Something went wrong changing the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                    }
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished changing job category." -Level Verbose
    }
}