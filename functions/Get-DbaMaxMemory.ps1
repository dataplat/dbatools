function Get-DbaMaxMemory {
    <#
    .SYNOPSIS
        Gets the 'Max Server Memory' configuration setting and the memory of the server.  Works on SQL Server 2000-2014.

    .DESCRIPTION
        This command retrieves the SQL Server 'Max Server Memory' configuration setting as well as the total physical installed on the server.

        Results are turned in megabytes (MB).

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $totalMemory = $server.PhysicalMemory

            # Some servers under-report by 1.
            if (($totalMemory % 1024) -ne 0) {
                $totalMemory = $totalMemory + 1
            }

            [pscustomobject]@{
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