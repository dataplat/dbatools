function Get-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Get-DbaAgentJobCategory retrieves the job categories.

    .DESCRIPTION
        Get-DbaAgentJobCategory makes it possible to retrieve the job categories.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category to filter out. If no category is used all categories will be returned.

    .PARAMETER CategoryType
        The type of category. This can be "LocalJob", "MultiServerJob" or "None".
        If no category is used all categories types will be returned.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

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
        https://dbatools.io/Get-DbaAgentJobCategory

    .EXAMPLE
        PS C:\> Get-DbaAgentJobCategory -SqlInstance sql1

        Return all the job categories.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobCategory -SqlInstance sql1 -Category 'Log Shipping'

        Return all the job categories that have the name 'Log Shipping'.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobCategory -SqlInstance sstad-pc -CategoryType MultiServerJob

        Return all the job categories that have a type MultiServerJob.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateNotNullOrEmpty()]
        [string[]]$Category,
        [ValidateSet("LocalJob", "MultiServerJob", "None")]
        [string]$CategoryType,
        [switch]$Force,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobCategories = $server.JobServer.JobCategories |
                Where-Object {
                    ($_.Name -in $Category -or !$Category) -and
                    ($_.CategoryType -in $CategoryType -or !$CategoryType)
                }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'ID', 'CategoryType', 'JobCount'

            try {
                foreach ($cat in $jobCategories) {
                    $jobCount = ($server.JobServer.Jobs | Where-Object { $_.CategoryID -eq $cat.ID }).Count

                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name JobCount -Value $jobCount

                    Select-DefaultView -InputObject $cat -Property $defaults
                }
            } catch {
                Stop-Function -Message "Something went wrong getting the job category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
            }
        }
    }
}