function Set-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Renames SQL Server Agent job categories to standardize naming conventions across instances.

    .DESCRIPTION
        Renames existing SQL Server Agent job categories by updating their names in the msdb database. This is particularly useful for standardizing job category naming conventions across multiple environments or correcting categories that were created with inconsistent names. The function validates that source categories exist and prevents renaming to names that already exist, helping maintain clean job organization within SQL Server Agent.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Specifies the existing job category name(s) to rename. The category must already exist in the SQL Server Agent on the target instance.
        Use this to identify which job categories need standardized naming across your environment.

    .PARAMETER NewName
        Specifies the new name(s) for the job category. The new name cannot already exist on the target instance.
        When renaming multiple categories, provide names in the same order as the Category parameter values.

    .PARAMETER Force
        Bypasses confirmation prompts and performs the rename operation without asking for user confirmation.
        Use this when scripting bulk category renames where manual confirmation would be impractical.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.JobCategory

        Returns one job category object per successfully renamed category via Get-DbaAgentJobCategory. The returned object represents the renamed SQL Server Agent job category with updated properties.

        Default display properties (via Select-DefaultView in Get-DbaAgentJobCategory):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the job category
        - ID: The unique identifier for the job category
        - CategoryType: The type of category (LocalJob, MultiServerJob, or DatabaseMaintenance)
        - JobCount: The number of jobs assigned to this category

        All properties from the base SMO JobCategory object are accessible using Select-Object * even though only default properties are displayed by default.

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
            Stop-Function -Message "You cannot rename multiple jobs to the same name"
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
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