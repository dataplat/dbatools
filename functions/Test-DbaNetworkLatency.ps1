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
        Specifies the query to be executed. By default, "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES" will be executed on master. To execute in other databases, use fully qualified object names.

    .PARAMETER Count
        Specifies how many times the query should be executed. By default, the query is executed three times.

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
        [string]$Query = "select top 100 * from INFORMATION_SCHEMA.TABLES",
        [int]$Count = 3,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $start = [System.Diagnostics.Stopwatch]::StartNew()
                $currentCount = 0
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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