function Test-DbaNetworkLatency {
    <#
    .SYNOPSIS
        Tests how long a query takes to return from SQL Server

    .DESCRIPTION
        This function is intended to help measure SQL Server network latency by establishing a connection and executing a simple query. This is a better than a simple ping because it actually creates the connection to the SQL Server and measures the time required for only the entire routine, but the duration of the query as well how long it takes for the results to be returned.

        By default, this command will execute "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" three times. It will then output how long the entire connection and command took, as well as how long *only* the execution of the command took.

        This allows you to see if the issue is with the connection or the SQL Server itself.

    .PARAMETER SqlInstance
        The SQL Server you want to run the test on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Query
        Specifies the SQL query to execute for latency testing. Defaults to "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" which provides consistent results across all SQL Server versions.
        Use a custom query when you need to test latency with queries similar to your actual workload, or when testing against specific databases using fully qualified object names.

    .PARAMETER Count
        Specifies how many times the query should be executed to calculate average latency measurements. Defaults to 3 executions.
        Increase this value when you need more precise average measurements or when testing intermittent network issues. Higher counts provide better statistical accuracy but take longer to complete.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, Network
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaNetworkLatency

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance queried, with latency measurements comparing total time vs. query execution time to isolate network delays.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ExecutionCount: The number of times the query was executed (same as -Count parameter)
        - Total: Total elapsed time for all executions (including connection and network overhead)
        - Average: Average elapsed time per query execution
        - ExecuteOnlyTotal: Total time spent in query execution only (excluding network overhead)
        - ExecuteOnlyAverage: Average query execution time per iteration
        - NetworkOnlyTotal: Time spent on network latency and connection overhead

        All time properties are returned as prettytimespan objects that display in human-readable format (ms, sec, etc.).

        The difference between Total and ExecuteOnlyTotal represents network latency and connection establishment time, helping DBAs identify whether performance issues originate from the network or the SQL Server instance itself.

    .EXAMPLE
        PS C:\> Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster

        Tests the round trip return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a and sqlcluster using Windows credentials.

    .EXAMPLE
        PS C:\> Test-DbaNetworkLatency -SqlInstance sqlserver2014a -SqlCredential $cred

        Tests the execution results return of "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" on sqlserver2014a using SQL credentials.

    .EXAMPLE
        PS C:\> Test-DbaNetworkLatency -SqlInstance sqlserver2014a, sqlcluster, sqlserver -Query "select top 10 * from otherdb.dbo.table" -Count 10

        Tests the execution results return of "select top 10 * from otherdb.dbo.table" 10 times on sqlserver2014a, sqlcluster, and sqlserver using Windows credentials.

    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Query = "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES",
        [int]$Count = 3,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $start = [System.Diagnostics.Stopwatch]::StartNew()
                $currentCount = 0
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                do {
                    if (++$currentCount -eq 1) {
                        $first = [System.Diagnostics.Stopwatch]::StartNew()
                    }
                    $null = $server.Query($query)
                    if ($currentCount -eq $count) {
                        $last = $first.Elapsed
                    }
                }
                while ($currentCount -lt $count)

                $end = $start.Elapsed
                $totalTime = $end.TotalMilliseconds
                $average = $totalTime / $count

                $totalWarm = $last.TotalMilliseconds
                if ($Count -eq 1) {
                    $averageWarm = $totalWarm
                } else {
                    $averageWarm = $totalWarm / $count
                }

                [PSCustomObject]@{
                    ComputerName     = $server.ComputerName
                    InstanceName     = $server.ServiceName
                    SqlInstance      = $server.DomainInstanceName
                    Count            = $count
                    Total            = [prettytimespan]::FromMilliseconds($totalTime)
                    Avg              = [prettytimespan]::FromMilliseconds($average)
                    ExecuteOnlyTotal = [prettytimespan]::FromMilliseconds($totalWarm)
                    ExecuteOnlyAvg   = [prettytimespan]::FromMilliseconds($averageWarm)
                    NetworkOnlyTotal = [prettytimespan]::FromMilliseconds($totalTime - $totalWarm)
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Count as ExecutionCount', Total, 'Avg as Average', ExecuteOnlyTotal, 'ExecuteOnlyAvg as ExecuteOnlyAverage', NetworkOnlyTotal #backwards compat
            } catch {
                Stop-Function -Message "Error occurred testing dba network latency: $_" -ErrorRecord $_ -Continue -Target $instance
            }
        }
    }
}