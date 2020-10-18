function Get-DbaRgWorkloadGroup {
    <#
    .SYNOPSIS
        Gets all Resource Governor Pool objects, including both internal and external

    .DESCRIPTION
        Gets all Resource Governor Pool objects, including both internal and external

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Allows input to be piped from Get-DbaRgResourcePool

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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