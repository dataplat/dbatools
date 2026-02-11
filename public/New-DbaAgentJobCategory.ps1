function New-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Creates new SQL Server Agent job categories for organizing and managing jobs.

    .DESCRIPTION
        Creates custom job categories in SQL Server Agent to help organize and classify jobs by function, department, or priority level. Job categories provide a way to group related jobs together for easier management and reporting, replacing the need to manually create categories through SQL Server Management Studio. You can specify whether the category is for local jobs, multi-server jobs, or general use, with LocalJob being the default type.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Specifies the name of the SQL Agent job category to create. Accepts multiple category names when you need to create several categories at once.
        Use descriptive names that reflect job functions like 'Database Maintenance', 'ETL Jobs', or 'Reporting' to help organize jobs by purpose or department.

    .PARAMETER CategoryType
        Defines the scope and purpose of the job category. Valid options are "LocalJob" for jobs that run on the local instance, "MultiServerJob" for jobs in multi-server environments, or "None" for general-purpose categories.
        Defaults to "LocalJob" when not specified, which is appropriate for most standalone SQL Server instances.

    .PARAMETER Force
        Suppresses confirmation prompts during category creation. Sets the confirmation preference to bypass interactive confirmation requests.
        Use this when automating category creation in scripts where manual confirmation is not desired or possible.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.JobCategory

        Returns one JobCategory object for each category created. The output is returned via Get-DbaAgentJobCategory after creation completes.

        Default display properties (via Select-DefaultView in Get-DbaAgentJobCategory):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Name of the job category
        - ID: Unique identifier for the category
        - CategoryType: Type of category (LocalJob, MultiServerJob, or None)
        - JobCount: Number of jobs assigned to this category

        All properties from the base SMO JobCategory object are accessible using Select-Object *.

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($cat in $Category) {
                if ($cat -in $server.JobServer.JobCategories.Name) {
                    Stop-Function -Message "Job category $cat already exists on $instance" -Target $instance -Continue
                } else {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the job category $cat")) {
                        try {
                            try {
                                $jobCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory($server.JobServer, $cat)
                            } catch {
                                if ($_.Exception.Message -match "newParent") {
                                    Stop-Function -Message "Cannot create agent job category through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $cat -Continue
                                    return
                                } else {
                                    throw
                                }
                            }
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