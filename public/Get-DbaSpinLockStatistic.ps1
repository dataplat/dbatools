function Get-DbaSpinLockStatistic {
    <#
    .SYNOPSIS
        Retrieves spinlock contention statistics from SQL Server's internal synchronization mechanisms

    .DESCRIPTION
        Queries sys.dm_os_spinlock_stats to return detailed statistics about SQL Server's spinlock usage and contention. Spinlocks are lightweight synchronization primitives that SQL Server uses internally for very brief waits when protecting critical code sections and memory structures.

        This information helps diagnose severe performance issues caused by spinlock contention, which typically manifests as high CPU usage with poor throughput. Common spinlock contention scenarios include tempdb allocation bottlenecks, excessive concurrent activity on specific database objects, or issues with SQL Server's internal data structures.

        Based on Paul Randal's advanced performance troubleshooting methodology, this data is essential when wait statistics show SOS_SCHEDULER_YIELD or other CPU-related waits that might indicate spinlock pressure.

        Returns:
                SpinLockName - The type of spinlock (e.g., LOCK_HASH, LOGCACHE_ACCESS)
                Collisions - Number of times threads had to wait for the spinlock
                Spins - Total number of spin cycles before acquiring the lock
                SpinsPerCollision - Average spins per collision (efficiency indicator)
                SleepTime - Total time spent sleeping when spins were exhausted
                Backoffs - Number of times the thread backed off before retrying

        Reference: https://www.sqlskills.com/blogs/paul/advanced-performance-troubleshooting-waits-latches-spinlocks/

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
        Tags: Diagnostic, SpinLockStatistics, Waits
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
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

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