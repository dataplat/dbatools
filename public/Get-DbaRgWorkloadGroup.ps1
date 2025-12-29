function Get-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Retrieves Resource Governor workload groups from SQL Server instances

    .DESCRIPTION
        Retrieves Resource Governor workload groups along with their configuration settings including CPU limits, memory grants, and parallelism controls. Workload groups define how resource requests are classified and managed within resource pools, allowing DBAs to control resource consumption for different types of workloads. This function is essential for monitoring and troubleshooting Resource Governor configurations to ensure optimal performance isolation between competing workloads.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts resource pool objects from Get-DbaRgResourcePool to retrieve workload groups from specific pools only.
        Use this to filter workload groups when you need to examine groups within particular resource pools instead of all workload groups across the instance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.WorkloadGroup

        Returns one WorkloadGroup object per workload group found in the specified resource pools. Each workload group object includes configuration settings for resource consumption limits and request handling behavior.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: Unique identifier for the workload group
        - Name: Name of the workload group
        - ExternalResourcePoolName: Name of the associated external resource pool (if applicable)
        - GroupMaximumRequests: Maximum number of concurrent requests allowed in the workload group (0 = unlimited)
        - Importance: Importance level of requests in this group (Low, Medium, High)
        - IsSystemObject: Boolean indicating if this is a system-defined workload group
        - MaximumDegreeOfParallelism: Maximum number of processors for parallel query execution (0 = unlimited)
        - RequestMaximumCpuTimeInSeconds: Maximum CPU time in seconds per request (0 = unlimited)
        - RequestMaximumMemoryGrantPercentage: Maximum memory grant as percentage of resource pool memory
        - RequestMemoryGrantTimeoutInSeconds: Timeout in seconds for memory grant requests

        Additional properties available (from SMO WorkloadGroup object):
        - ClassifierFunction: Name of the scalar classifier function (if any)
        - CreateDate: DateTime when the workload group was created
        - ModifyDate: DateTime when the workload group was last modified
        - Parent: Reference to the parent ResourcePool object
        - State: Current state of the workload group object

        All properties from the base SMO object are accessible using Select-Object *.

    .NOTES
        Tags: ResourceGovernor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRgWorkloadGroup

    .EXAMPLE
        PS C:\> Get-DbaRgWorkloadGroup -SqlInstance sql2017

        Gets the workload groups on sql2017

    .EXAMPLE
        PS C:\> Get-DbaResourceGovernor -SqlInstance sql2017 | Get-DbaRgResourcePool | Get-DbaRgWorkloadGroup

        Gets the workload groups on sql2017

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.ResourcePool[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRgResourcePool -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        foreach ($pool in $InputObject) {
            $group = $pool.WorkloadGroups
            if ($group) {
                $group | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $pool.ComputerName
                $group | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $pool.InstanceName
                $group | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $pool.SqlInstance
                $group | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, ExternalResourcePoolName, GroupMaximumRequests, Importance, IsSystemObject, MaximumDegreeOfParallelism, RequestMaximumCpuTimeInSeconds, RequestMaximumMemoryGrantPercentage, RequestMemoryGrantTimeoutInSeconds
            }
        }
    }
}