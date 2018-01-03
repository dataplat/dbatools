function New-DbaAgentJobCategory {
    <#
.SYNOPSIS
New-DbaAgentJobCategory creates a new job category.

.DESCRIPTION
New-DbaAgentJobCategory makes it possible to create a job category that can be used with jobs.
It returns an array of the job(s) created .

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

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
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Category

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaAgentJobCategory

.EXAMPLE
New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1'

Creates a new job category with the name 'Category 1'.

.EXAMPLE
New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 2' -CategoryType MultiServerJob

Creates a new job category with the name 'Category 2' and assign the category type for a multi server job.

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [ValidateSet("LocalJob", "MultiServerJob", "None")]
        [string]$CategoryType,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        # Check the category type
        if (-not $CategoryType) {
            # Setting category type to default
            Write-Message -Message "Setting the category type to 'LocalJob'" -Level Verbose
            $CategoryType = "LocalJob"
        }
    }

    process {

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cat in $Category) {
                # Check if the category already exists
                if ($cat -in $server.JobServer.JobCategories.Name) {
                    Stop-Function -Message "Job category $cat already exists on $instance" -Target $instance -Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the job category $cat")) {
                        try {
                            $jobcategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory($server.JobServer, $cat)
                            $jobcategory.CategoryType = $CategoryType

                            $jobcategory.Create()

                            $server.JobServer.Refresh()
                        }
                        catch {
                            Stop-Function -Message "Something went wrong creating the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                        }

                    } # if should process

                } # end else category exists

                # Return the job category
                Get-DbaAgentJobCategory -SqlInstance $instance -Category $cat

            } # for each category

        } # for each instance
    }

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job category." -Level Verbose
    }

}