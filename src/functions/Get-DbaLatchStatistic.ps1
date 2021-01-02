function Get-DbaLatchStatistic {
    <#
    .SYNOPSIS
        Displays latch statistics from sys.dm_os_latch_stats

    .DESCRIPTION
        This command is based off of Paul Randal's post "Advanced SQL Server performance tuning"

        Returns:
                LatchClass
                WaitSeconds
                WaitCount
                Percentage
                AverageWaitSeconds
                URL

        Reference:  https://www.sqlskills.com/blogs/paul/advanced-performance-troubleshooting-waits-latches-spinlocks/
                    https://www.sqlskills.com/blogs/paul/most-common-latch-classes-and-what-they-mean/

    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Threshold
        Threshold, in percentage of all latch stats on the system. Default per Paul's post is 95%.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LatchStatistics, Waits
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLatchStatistic

    .EXAMPLE
        PS C:\> Get-DbaLatchStatistic -SqlInstance sql2008, sqlserver2012

        Check latch statistics for servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 98

        Check latch statistics on server sql2008 for thresholds above 98%

    .EXAMPLE
        PS C:\> $output = Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 100 | Select-Object * | ConvertTo-DbaDataTable

        Collects all latch statistics on server sql2008 into a Data Table.

    .EXAMPLE
        PS C:\> 'sql2008','sqlserver2012' | Get-DbaLatchStatistic

        Get latch statistics for servers sql2008 and sqlserver2012 via pipline

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaLatchStatistic -SqlInstance sql2008 -SqlCredential $cred

        Connects using sqladmin credential and returns latch statistics from sql2008

    .EXAMPLE
        PS C:\> $output = Get-DbaLatchStatistic -SqlInstance sql2008
        PS C:\> $output
        PS C:\> foreach ($row in ($output | Sort-Object -Unique Url)) { Start-Process ($row).Url }

        Displays the output then loads the associated sqlskills website for each result. Opens one tab per unique URL.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 95,
        [switch]$EnableException
    )

    BEGIN {
        $sql = "WITH [Latches] AS
               (
                   SELECT
                       [latch_class],
                       [wait_time_ms] / 1000.0 AS [WaitS],
                       [waiting_requests_count] AS [WaitCount],
                       Case WHEN SUM ([wait_time_ms]) OVER() = 0 THEN NULL ELSE 100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() END AS [Percentage],
                       ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                   FROM sys.dm_os_latch_stats
                   WHERE [latch_class] NOT IN (N'BUFFER')
               )
               SELECT
                   MAX ([W1].[latch_class]) AS [LatchClass],
                   CAST (MAX ([W1].[WaitS]) AS DECIMAL(14, 2)) AS [WaitSeconds],
                   MAX ([W1].[WaitCount]) AS [WaitCount],
                   CAST (MAX ([W1].[Percentage]) AS DECIMAL(14, 2)) AS [Percentage],
                   CAST ((MAX ([W1].[WaitS]) / MAX ([W1].[WaitCount])) AS DECIMAL (14, 4)) AS [AvgWaitSeconds],
                   CAST ('https://www.sqlskills.com/help/latches/' + MAX ([W1].[latch_class]) as XML) AS [URL]
               FROM [Latches] AS [W1]
               INNER JOIN [Latches] AS [W2]
                   ON [W2].[RowNum] <= [W1].[RowNum]
               GROUP BY [W1].[RowNum]
               HAVING SUM ([W2].[Percentage]) - MAX ([W1].[Percentage]) < $Threshold;"

        Write-Message -Level Debug -Message $sql
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                Return
            }
            Write-Message -Level Verbose -Message "Connected to $instance"

            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName       = $server.ComputerName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.DomainInstanceName
                    WaitType           = $row.LatchClass
                    WaitSeconds        = $row.WaitSeconds
                    WaitCount          = $row.WaitCount
                    Percentage         = $row.Percentage
                    AverageWaitSeconds = $row.AvgWaitSeconds
                    URL                = $row.URL
                }
            }
        }
    }
}