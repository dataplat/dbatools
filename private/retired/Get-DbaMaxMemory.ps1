function Get-DbaMaxMemory {
    <#
    .SYNOPSIS
        Retrieves SQL Server max memory configuration and compares it to total physical server memory

    .DESCRIPTION
        This command retrieves the SQL Server 'Max Server Memory' configuration setting alongside the total physical memory installed on the server. This comparison helps identify potential memory configuration issues that can impact SQL Server performance.

        Use this function to audit memory settings across your environment, troubleshoot performance issues related to memory pressure, or verify that SQL Server isn't configured to use more memory than physically available. The function is particularly useful for finding instances with the default max memory setting (2147483647 MB) that should be properly configured based on available physical memory.

        Results are returned in megabytes (MB) for both the configured max memory and total physical memory values.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: MaxMemory, Memory
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaMaxMemory

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance specified, containing memory configuration and physical memory information for comparison.

        Default display properties (via Select-DefaultView):
        - ComputerName: Name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: Full SQL Server instance name (computer\instance format)
        - Total: Total physical memory on the server in megabytes (MB)
        - MaxValue: Configured max server memory setting in megabytes (MB)

        Additional available property:
        - Server: The SMO Server object representing the connected SQL Server instance; accessible for piping or further operations

        Use Select-Object * to access the Server property, or pipe the output to other commands for advanced scenarios.

    .EXAMPLE
        PS C:\> Get-DbaMaxMemory -SqlInstance sqlcluster, sqlserver2012

        Get memory settings for instances "sqlcluster" and "sqlserver2012". Returns results in megabytes (MB).

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlcluster | Get-DbaMaxMemory | Where-Object { $_.MaxValue -gt $_.Total }

        Find all servers in Server Central Management Server that have 'Max Server Memory' set to higher than the total memory of the server (think 2147483647)

    .EXAMPLE
        PS C:\> Find-DbaInstance -ComputerName localhost | Get-DbaMaxMemory | Format-Table -AutoSize

        Scans localhost for instances using the browser service, traverses all instances and displays memory settings in a formatted table.
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $totalMemory = $server.PhysicalMemory

            # Some servers under-report by 1.
            if (($totalMemory % 1024) -ne 0) {
                $totalMemory = $totalMemory + 1
            }

            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Total        = [int]$totalMemory
                MaxValue     = [int]$server.Configuration.MaxServerMemory.ConfigValue
                Server       = $server # This will allowing piping a non-connected object
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Total, MaxValue
        }
    }
}