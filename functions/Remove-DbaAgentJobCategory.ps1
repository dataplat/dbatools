function Remove-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Remove-DbaAgentJobCategory removes a job category.

    .DESCRIPTION
        Remove-DbaAgentJobCategory makes it possible to remove a job category.
        Be assured that the category you want to remove is not used with other jobs. If another job uses this category it will be get the category [Uncategorized (Local)].

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category.

    .PARAMETER CategoryType
        The type of category. This can be "LocalJob", "MultiServerJob" or "None".
        If no category is used all categories types will be removed.

    .PARAMETER InputObject
        Allows piping from Get-DbaAgentJobCategory.

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
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobCategory -SqlInstance sql1 -Category 'Category 1'

        Remove the job category Category 1 from the instance.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobCategory -SqlInstance sql1 -Category Category1, Category2, Category3

        Remove multiple job categories from the instance.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobCategory -SqlInstance sql1, sql2, sql3 -Category Category1, Category2, Category3

        Remove multiple job categories from the multiple instances.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobCategory -SqlInstance SRV1 | Out-GridView -Title 'Select SQL Agent job category(-ies) to drop' -OutputMode Multiple | Remove-DbaAgentJobCategory

        Using a pipeline this command gets all SQL Agent job category(-ies) on SRV1, lets the user select those to remove and then removes the selected SQL Agent job category(-ies).

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Category,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet("LocalJob", "MultiServerJob", "None")]
        [string[]]$CategoryType,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobCategory[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $jobCategories = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $jobCategories = Get-DbaAgentJobCategory @params
        } else {
            $jobCategories += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentJobCategory.
        foreach ($jobCategory in $jobCategories) {
            if ($PSCmdlet.ShouldProcess($jobCategory.Parent.Parent.Name, "Removing the SQL Agent category(-ies) $($jobCategory.Name) on $($jobCategory.Parent.Parent.Name)")) {
                $output = [pscustomobject]@{
                    ComputerName = $jobCategory.Parent.Parent.ComputerName
                    InstanceName = $jobCategory.Parent.Parent.ServiceName
                    SqlInstance  = $jobCategory.Parent.Parent.DomainInstanceName
                    Name         = $jobCategory.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $jobCategory.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the SQL Agent job category(-ies) $($jobCategory.Name) on $($jobCategory.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}