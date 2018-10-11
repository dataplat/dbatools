function Get-DbaLatchStatistic {
    <#
        .SYNOPSIS
            Displays wait statistics

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
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Threshold
            Threshold, in percentage of all latch stats on the system. Default per Paul's post is 95%.

        .PARAMETER WhatIf
            Shows what would happen if the cmdlet runs. The cmdlet is not run.

        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Patrick Flynn, @sqllensman

            Tags: LatchStatistics
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaLatchStatistic

        .EXAMPLE
            Get-DbaLatchStatistic -SqlInstance sql2008, sqlserver2012

            Check latch statistics for servers sql2008 and sqlserver2012

        .EXAMPLE
            Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 98

            Check latch statistics on server sql2008 for thresholds above 98%

        .EXAMPLE
            $output = Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 100 | Select * | ConvertTo-DbaDataTable

            Collects all latch statistics on server sql2008 into a Data Table.

        .EXAMPLE
            'sql2008','sqlserver2012' | Get-DbaLatchStatistic
            Get latch statistics for servers sql2008 and sqlserver2012 via pipline

        .EXAMPLE
            $cred = Get-Credential sqladmin
            Get-DbaLatchStatistic -SqlInstance sql2008 -SqlCredential $cred

            Connects using sqladmin credential and returns latch statistics from sql2008

        .EXAMPLE
            $output = Get-DbaLatchStatistic -SqlInstance sql2008
            $output
            foreach ($row in ($output | Sort-Object -Unique Url)) { Start-Process ($row).Url }

            Displays the output then loads the associated sqlskills website for each result. Opens one tab per unique URL.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 95,
        [switch][Alias('Silent')]$EnableException
    )

    BEGIN {

       $sql = "WITH [Latches] AS
               (
                   SELECT
                       [latch_class],
                       [wait_time_ms] / 1000.0 AS [WaitS],
                       [waiting_requests_count] AS [WaitCount],
                       100.0 * [wait_time_ms] / SUM ([wait_time_ms]) OVER() AS [Percentage],
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
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                Return
            }
            Write-Message -Level Verbose -Message "Connected to $instance"

            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2005 (v9)."
                return
            }

            if ($Pscmdlet.ShouldProcess($instance, "Collecting data from sys.dm_os_latch_stats")) {
                foreach ($row in $server.Query($sql)) {
                    [PSCustomObject]@{
                        ComputerName           = $server.NetName
                        InstanceName           = $server.ServiceName
                        SqlInstance            = $server.DomainInstanceName
                        WaitType               = $row.LatchClass
                        WaitSeconds            = $row.WaitSeconds
                        WaitCount              = $row.WaitCount
                        Percentage             = $row.Percentage
                        AverageWaitSeconds     = $row.AvgWaitSeconds
                        URL                    = $row.URL
                    }
                }
            }
        }
    }
}