function New-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        New-DbaAgentJobCategory creates a new job category.

    .DESCRIPTION
        New-DbaAgentJobCategory makes it possible to create a job category that can be used with jobs.
        It returns an array of the job categories created .

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category

    .PARAMETER CategoryType
        The type of category. This can be "LocalJob", "MultiServerJob" or "None".
        The default is "LocalJob" and will automatically be set when no option is chosen.

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
        https://dbatools.io/New-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1'

        Creates a new job category with the name 'Category 1'.

    .EXAMPLE
        PS C:\> New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 2' -CategoryType MultiServerJob

        Creates a new job category with the name 'Category 2' and assign the category type for a multi server job.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [ValidateSet("LocalJob", "MultiServerJob", "None")]
        [string]$CategoryType,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if (-not $CategoryType) {
            Write-Message -Message "Setting the category type to 'LocalJob'" -Level Verbose
            $CategoryType = "LocalJob"
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cat in $Category) {
                if ($cat -in $server.JobServer.JobCategories.Name) {
                    Stop-Function -Message "Job category $cat already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the job category $cat")) {
                        try {
                            $jobCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory($server.JobServer, $cat)
                            $jobCategory.CategoryType = $CategoryType

                            $jobCategory.Create()

                            $server.JobServer.Refresh()
                        } catch {
                            Stop-Function -Message "Something went wrong creating the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                        }
                    }
                }
                Get-DbaAgentJobCategory -SqlInstance $server -Category $cat
            }
        }
    }
}