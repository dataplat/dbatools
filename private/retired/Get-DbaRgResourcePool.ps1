function Get-DbaRgResourcePool {
    <#
    .SYNOPSIS
        Retrieves SQL Server Resource Governor resource pools with their CPU, memory, and IOPS configuration settings

    .DESCRIPTION
        Retrieves detailed information about SQL Server Resource Governor resource pools, including both internal (CPU/memory) and external (R/Python) pools. Shows current configuration settings for minimum and maximum CPU percentages, memory percentages, and IOPS limits per volume. Essential for monitoring resource allocation, troubleshooting performance bottlenecks, and auditing resource governance policies across your SQL Server instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts Resource Governor objects from Get-DbaResourceGovernor for pipeline processing.
        Use this when you need to filter or process resource pools from multiple instances collected earlier in your script.

    .PARAMETER Type
        Specifies whether to retrieve Internal resource pools (CPU/memory) or External resource pools (R/Python services).
        Internal pools control SQL Server workloads, while External pools govern Machine Learning Services resource consumption.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ResourcePool (Internal pools) or Microsoft.SqlServer.Management.Smo.ExternalResourcePool (External pools)

        Returns one ResourcePool or ExternalResourcePool object per resource pool found on the instance. The object type depends on the -Type parameter:
        - Type "Internal" (default): Returns Microsoft.SqlServer.Management.Smo.ResourcePool objects
        - Type "External": Returns Microsoft.SqlServer.Management.Smo.ExternalResourcePool objects

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: Unique identifier for the resource pool
        - Name: Name of the resource pool
        - CapCpuPercentage: CPU cap percentage (0-100 for External pools, always 0 for Internal pools)
        - IsSystemObject: Boolean indicating if this is a system-defined resource pool
        - MaximumCpuPercentage: Maximum CPU percentage allocated to this pool (0-100)
        - MaximumIopsPerVolume: Maximum I/O operations per second per volume (External pools only)
        - MaximumMemoryPercentage: Maximum memory percentage allocated to this pool (0-100)
        - MinimumCpuPercentage: Minimum CPU percentage reserved for this pool (0-100)
        - MinimumIopsPerVolume: Minimum I/O operations per second per volume (External pools only)
        - MinimumMemoryPercentage: Minimum memory percentage reserved for this pool (0-100)
        - WorkloadGroups: Collection of workload groups associated with this resource pool

        Additional properties available (from SMO ResourcePool or ExternalResourcePool objects):
        - CreateDate: DateTime when the resource pool was created
        - ModifyDate: DateTime when the resource pool was last modified
        - Parent: Reference to the parent ResourceGovernor object
        - State: Current state of the resource pool object (Existing, Creating, Pending, etc.)

        All properties from the base SMO object are accessible using Select-Object *.

    .NOTES
        Tags: ResourceGovernor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRgResourcePool

    .EXAMPLE
        PS C:\> Get-DbaRgResourcePool -SqlInstance sql2016

        Gets the internal resource pools on sql2016

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool

        Gets the internal resource pools on Sql1 and Sql2/sqlexpress instances

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool -Type External

        Gets the external resource pools on Sql1 and Sql2/sqlexpress instances


    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Internal", "External")]
        [string]$Type = "Internal",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.ResourceGovernor[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaResourceGovernor -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        foreach ($resourcegov in $InputObject) {
            if ($Type -eq "External") {
                $respool = $resourcegov.ExternalResourcePools
                if ($respool) {
                    $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $resourcegov.ComputerName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $resourcegov.InstanceName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $resourcegov.SqlInstance
                    $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
                }
            } else {
                $respool = $resourcegov.ResourcePools
                if ($respool) {
                    $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $resourcegov.ComputerName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $resourcegov.InstanceName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $resourcegov.SqlInstance
                    $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
                }
            }
        }
    }
}