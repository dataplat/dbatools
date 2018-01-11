function Get-DbaAgentJobCategory {
    <#
.SYNOPSIS
Get-DbaAgentJobCategory retrieves the job categories.

.DESCRIPTION
Get-DbaAgentJobCategory makes it possible to retrieve the job categories.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Category
The name of the category to filter out. If no category is used all catgories will be returned.

.PARAMETER CategoryType
The type of category. This can be "LocalJob", "MultiServerJob" or "None".
If no category is used all catgories types will be returned.

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
https://dbatools.io/Get-DbaAgentJobCategory

.EXAMPLE
Get-DbaAgentJobCategory -SqlInstance sql1

Return all the job categories.

.EXAMPLE
Get-DbaAgentJobCategory -SqlInstance sql1 -Category 'Log Shipping'

Return all the job categories that have the name 'Log Shipping'.

.EXAMPLE
Get-DbaAgentJobCategory -SqlInstance sstad-pc -CategoryType MultiServerJob

Return all the job categories that have a type MultiServerJob.

#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [ValidateSet("LocalJob", "MultiServerJob", "None")]
        [string]$CategoryType,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # get all the job categories
            $jobCategories = $server.JobServer.JobCategories |
                Where-Object {
                ($_.Name -in $Category -or !$Category) -and
                ($_.CategoryType -in $CategoryType -or !$CategoryType)
            }

            # Set the default output
            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'ID', 'CategoryType', 'JobCount'

            # Loop through each of the categories
            try {
                foreach ($cat in $jobCategories) {

                    # Get the jobs associated with the category
                    $jobCount = ($server.JobServer.Jobs | Where-Object {$_.CategoryID -eq $cat.ID}).Count

                    # Add new properties to the category object
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name JobCount -Value $jobCount

                    # Show the result
                    Select-DefaultView -InputObject $cat -Property $defaults
                }
            }
            catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified" -Continue
            }

        } # for each instance

    } # end process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished retrieving job category." -Level Verbose
    }


}