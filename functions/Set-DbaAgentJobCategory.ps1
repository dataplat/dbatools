function Set-DbaAgentJobCategory {
    <#
.SYNOPSIS
Set-DbaAgentJobCategory changes a job category.

.DESCRIPTION
Set-DbaAgentJobCategory makes it possible to change a job category.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

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
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Category

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Set-DbaAgentJobCategory

.EXAMPLE
New-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1' -NewName 'Category 2'

Change the name of the category from 'Category 1' to 'Category 2'.

.EXAMPLE
Set-DbaAgentJobCategory -SqlInstance sql1, sql2 -Category Category1, Category2 -NewName cat1, cat2

Rename multiple jobs in one go on multiple servers.

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [string[]]$NewName,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        # Create array list to hold the results
        $collection = New-Object System.Collections.ArrayList

        # Check if multiple categories are being changed
        if ($Category.Count -gt 1 -and $NewName.Count -eq 1) {
            Stop-Function -Message "You cannot rename multiple jobs to the same name" -Target $instance
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
                        $originalCategoryName = $currentCategory.Name
                        $newCategoryName = $null

                        # Check if the job category needs to be renamed
                        if ($NewName) {
                            $currentCategory.Rename($NewName[$Category.IndexOf($cat)])
                            $newCategoryName = $currentCategory.Name
                        }

                        # Set up the custom object
                        $null = $collection.Add([PSCustomObject]@{
                                ComputerName    = $server.NetName
                                InstanceName    = $server.ServiceName
                                SqlInstance     = $server.DomainInstanceName
                                CategoryName    = $originalCategoryName
                                NewCategoryName = $newCategoryName
                            })

                    }
                    catch {
                        Stop-Function -Message "Something went wrong changing the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                    }

                } # if should process

            } # for each category

        } # foreach instance

        # Return result
        return $collection

    } # end process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished changing job category." -Level Verbose
    }

}