function Get-DbaAgentJobCategory {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent job categories with usage counts and filtering options

    .DESCRIPTION
        Returns SQL Server Agent job categories from one or more instances, showing how many jobs are assigned to each category. Job categories help organize and group related SQL Agent jobs for easier management and reporting. This function retrieves both built-in categories (like Database Maintenance, Log Shipping) and custom categories created by DBAs. You can filter by specific category names or types (LocalJob for single-instance jobs, MultiServerJob for MSX/TSX environments, or None for uncategorized jobs) to focus on particular organizational schemes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Specifies one or more job category names to return, filtering the results to only those categories. Accepts multiple values and supports built-in categories like 'Database Maintenance', 'Log Shipping', 'Replication', and custom categories created by DBAs.
        Use this when you need to check specific categories for job assignments or verify custom organizational schemes. If not specified, all job categories are returned.

    .PARAMETER CategoryType
        Filters job categories by their deployment type: 'LocalJob' for single-instance jobs, 'MultiServerJob' for Master Server/Target Server (MSX/TSX) environments, or 'None' for uncategorized jobs.
        Use this in MSX/TSX configurations to distinguish between locally managed jobs and multi-server jobs, or to identify jobs that haven't been assigned a proper category. If not specified, all category types are returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, Category
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.JobCategory

        Returns one JobCategory object per job category on the SQL Server instance. Custom properties are added to provide connection context and job count information.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the job category
        - ID: The unique identifier of the job category
        - CategoryType: The type of category (LocalJob, MultiServerJob, or None)
        - JobCount: The number of jobs currently assigned to this category (integer)

        Additional properties available (from SMO JobCategory object):
        - Parent: Reference to the parent JobServer object
        - Urn: The Unified Resource Name that uniquely identifies the job category
        - State: The state of the object (Existing, Creating, Dropping, Pending)

        All properties from the base SMO JobCategory object are accessible by using Select-Object *.

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
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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