function Get-DbaSpinLockStatistic {
    <#
    .SYNOPSIS
        Displays information from sys.dm_os_spinlock_stats.  Works on SQL Server 2008 and above.

    .DESCRIPTION
            This command is based off of Paul Randal's post "Advanced SQL Server performance tuning"

            Returns:
                    SpinLockName
                    Collisions
                    Spins
                    SpinsPerCollision
                    SleepTime
                    Backoffs

            Reference:  https://www.sqlskills.com/blogs/paul/advanced-performance-troubleshooting-waits-latches-spinlocks/

    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SpinLockStatistics, Waits
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSpinLockStatistic

    .EXAMPLE
        PS C:\> Get-DbaSpinLockStatistic -SqlInstance sql2008, sqlserver2012

        Get SpinLock Statistics for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> $output = Get-DbaSpinLockStatistic -SqlInstance sql2008 | Select-Object * | ConvertTo-DbaDataTable

        Collects all SpinLock Statistics on server sql2008 into a Data Table.

    .EXAMPLE
        PS C:\> 'sql2008','sqlserver2012' | Get-DbaSpinLockStatistic

        Get SpinLock Statistics for servers sql2008 and sqlserver2012 via pipline

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaSpinLockStatistic -SqlInstance sql2008 -SqlCredential $cred

        Connects using sqladmin credential and returns SpinLock Statistics from sql2008
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    BEGIN {

        $sql = "SELECT
                	name,
                	collisions,
                	spins,
                	spins_per_collision,
                	sleep_time,
                	backoffs
                FROM sys.dm_os_spinlock_stats;"

        Write-Message -Level Debug -Message $sql
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Connected to $instance"

            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.ServiceName
                    SqlInstance       = $server.DomainInstanceName
                    SpinLockName      = $row.name
                    Collisions        = $row.collisions
                    Spins             = $row.spins
                    SpinsPerCollision = $row.spins_per_collision
                    SleepTime         = $row.sleep_time
                    Backoffs          = $row.backoffs
                }
            }
        }
    }
}