function Get-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Retrieves Resource Governor configuration and status from SQL Server instances

    .DESCRIPTION
        Retrieves the Resource Governor object containing configuration details, enabled status, and associated resource pools. Resource Governor allows DBAs to manage SQL Server workload and resource consumption by setting limits on CPU, memory, and I/O usage for different workloads. This function helps you quickly check if Resource Governor is enabled, view classifier functions, and examine current resource pool configurations without writing custom T-SQL queries.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        https://dbatools.io/Get-DbaResourceGovernor

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ResourceGovernor

        Returns one ResourceGovernor object per instance. The object represents the Resource Governor configuration and includes properties for enabled status, classifier function configuration, and resource pool management.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ClassifierFunction: The fully qualified name of the Resource Governor classifier function (e.g., [dbo].[fn_classifier])
        - Enabled: Boolean indicating if Resource Governor is enabled on the instance
        - MaxOutstandingIOPerVolume: Maximum number of outstanding I/O operations allowed per disk volume
        - ReconfigurePending: Boolean indicating if a Resource Governor configuration change is pending and requires ALTER RESOURCE GOVERNOR RECONFIGURE
        - ResourcePools: Collection of ResourcePool objects defined on the instance
        - ExternalResourcePools: Collection of ExternalResourcePool objects for machine learning workloads (SQL Server 2016+)

        Additional properties available (from SMO ResourceGovernor object):
        - Parent: Reference to the parent Server object
        - State: Current state of the SMO object (Existing, Creating, Pending, etc.)
        - Urn: The unified resource name for the ResourceGovernor object

        All properties from the base SMO ResourceGovernor object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaResourceGovernor -SqlInstance sql2016

        Gets the resource governor object of the SqlInstance sql2016

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor

        Gets the resource governor object on Sql1 and Sql2/sqlexpress instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $resourcegov = $server.ResourceGovernor

            if ($resourcegov) {
                Add-Member -Force -InputObject $resourcegov -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $resourcegov -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $resourcegov -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            }

            Select-DefaultView -InputObject $resourcegov -Property ComputerName, InstanceName, SqlInstance, ClassifierFunction, Enabled, MaxOutstandingIOPerVolume, ReconfigurePending, ResourcePools, ExternalResourcePools
        }
    }
}