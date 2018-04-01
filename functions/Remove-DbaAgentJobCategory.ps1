function Remove-DbaAgentJobCategory {

    <#
.SYNOPSIS
Remove-DbaAgentJobCategory removes a job category.

.DESCRIPTION
Remove-DbaAgentJobCategory makes it possible to remove a job category.
Be assured that the category you want to remove is not used with other jobs. If another job uses this category it will be get the category [Uncategorized (Local)].

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Category

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
https://dbatools.io/Remove-DbaAgentJobCategory

.EXAMPLE
Remove-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1'

Remove the job category Category 1 from the instance.

.EXAMPLE
Remove-DbaAgentJobCategory -SqlInstance sql1 -Category Category1, Category2, Category3

Remove multiple job categories from the instance.

.EXAMPLE
Remove-DbaAgentJobCategory -SqlInstance sql1, sql2, sql3 -Category Category1, Category2, Category3

Remove multiple job categories from the multiple instances.

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
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

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

                # Check if the job category exists
                if ($cat -notin $server.JobServer.JobCategories.Name) {
                    Stop-Function -Message "Job category $cat doesn't exist on $instance" -Target $instance -Continue
                }

                # Remove the category
                if ($PSCmdlet.ShouldProcess($instance, "Changing the job category $Category")) {
                    try {
                        # Get the category
                        $currentCategory = $server.JobServer.JobCategories[$cat]

                        Write-Message -Message "Removing job category $cat" -Level Verbose

                        $currentCategory.Drop()
                    }
                    catch {
                        Stop-Function -Message "Something went wrong removing the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
                    }

                } #if should process

            } # for each category

        } # for each instance

    } # end process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished removing job category." -Level Verbose
    }

}