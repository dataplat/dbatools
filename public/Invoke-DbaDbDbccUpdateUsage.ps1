function Invoke-DbaDbDbccUpdateUsage {
    <#
    .SYNOPSIS
        Corrects page and row count inaccuracies in SQL Server catalog views using DBCC UPDATEUSAGE

    .DESCRIPTION
        Executes the DBCC UPDATEUSAGE command to identify and fix metadata inconsistencies in catalog views that track space usage information. When these internal counters become inaccurate, system procedures like sp_spaceused return incorrect database and table size reports, making capacity planning and troubleshooting difficult.

        This command is essential when you notice discrepancies between actual database file sizes and reported space usage, or when sp_spaceused shows unexpected results after bulk operations, index rebuilds, or database migrations. The function can target entire instances, specific databases, individual tables, or even single indexes depending on your troubleshooting needs.

        Common scenarios include fixing space reports after large data imports, resolving inconsistencies following database restores, and correcting metadata after index maintenance operations. The command reads actual page allocations and updates the system catalog views to reflect accurate usage statistics.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-updateusage-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to update usage statistics for. Accepts database names or IDs.
        When omitted, DBCC UPDATEUSAGE runs against all accessible databases on the instance.
        Use this to target specific databases when you know which ones have inaccurate space usage reports.

    .PARAMETER Table
        Specifies a single table or indexed view to update usage statistics for. Accepts table names or object IDs.
        When omitted, DBCC UPDATEUSAGE processes all tables and indexed views in the specified database(s).
        Use this when sp_spaceused reports incorrect sizes for a specific table after bulk operations or index maintenance.

    .PARAMETER Index
        Specifies a single index to update usage statistics for. Accepts index names or index IDs.
        Requires the Table parameter to be specified and updates statistics only for that specific index.
        Use this for targeted correction when you know a particular index has inaccurate metadata after rebuilds or reorganization.

    .PARAMETER NoInformationalMessages
        Suppresses informational messages during DBCC UPDATEUSAGE execution using the NO_INFOMSGS option.
        Use this in automated scripts or when processing many objects to reduce output volume and focus on actual problems.

    .PARAMETER CountRows
        Forces DBCC UPDATEUSAGE to recalculate and update row counts in addition to page counts using the COUNT_ROWS option.
        Use this when sp_spaceused shows incorrect row counts, typically after bulk insert/delete operations or database restores.
        Note that this option increases execution time as SQL Server must physically count all rows in affected tables.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDbccUpdateUsage

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccUpdateUsage -SqlInstance SqlServer2017

        Runs the command DBCC UPDATEUSAGE to update the page or row counts or both for all objects in all databases for the instance SqlServer2017. Connect using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccUpdateUsage -SqlInstance SqlServer2017 -Database CurrentDB

        Runs the command DBCC UPDATEUSAGE to update the page or row counts or both for all objects in the CurrentDB database for the instance SqlServer2017. Connect using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbDbccUpdateUsage -SqlInstance SqlServer2017 -Database CurrentDB -Table Sometable

        Connects to CurrentDB on instance SqlServer2017 using Windows Authentication and runs the command DBCC UPDATEUSAGE(SometableId) to update the page or row counts for all indexes in the table.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Invoke-DbaDbDbccUpdateUsage -SqlInstance SqlServer2017 -SqlCredential $cred -Database CurrentDB -Table 'SometableId -Index IndexName -NoInformationalMessages -CountRows

        Connects to CurrentDB on instance SqlServer2017 using sqladmin credential and runs the command DBCC UPDATEUSAGE(SometableId, IndexName) WITH NO_INFOMSGS, COUNT_ROWS to update the page or row counts.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Invoke-DbaDbDbccUpdateUsage -WhatIf

        Displays what will happen if command DBCC UPDATEUSAGE is called against all databases on Sql1 and Sql2/sqlexpress.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Table,
        [string]$Index,
        [switch]$NoInformationalMessages,
        [switch]$CountRows,
        [switch]$EnableException
    )
    begin {

        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC UPDATEUSAGE(#options#)")
        if (Test-Bound -ParameterName NoInformationalMessages) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            if (Test-Bound -ParameterName CountRows) {
                $null = $stringBuilder.Append(", COUNT_ROWS")
            }
        } else {
            if (Test-Bound -ParameterName CountRows) {
                $null = $stringBuilder.Append(" WITH COUNT_ROWS")
            }
        }
        Write-Message -Message "$($StringBuilder.ToString())" -Level Verbose

    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if (Test-Bound -ParameterName Database) {
                $dbs = $dbs | Where-Object { ($_.Name -In $Database) -or ($_.ID -In $Database) }
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                try {
                    $query = $StringBuilder.ToString()
                    if (Test-Bound -ParameterName Table) {
                        if (Test-Bound -ParameterName Index) {
                            if ($Table -match '^\d+$') {
                                if ($Index -match '^\d+$') {
                                    $query = $query.Replace('#options#', "'$($db.name)', $Table, $Index")
                                } else {
                                    $query = $query.Replace('#options#', "'$($db.name)', $Table, '$Index'")
                                }
                            } else {
                                if ($Index -match '^\d+$') {
                                    $query = $query.Replace('#options#', "'$($db.name)', '$Table', $Index")
                                } else {
                                    $query = $query.Replace('#options#', "'$($db.name)', '$Table', '$Index'")
                                }
                            }
                        } else {
                            if ($Table -match '^\d+$') {
                                $query = $query.Replace('#options#', "'$($db.name)', $Table")
                            } else {
                                $query = $query.Replace('#options#', "'$($db.name)', '$Table'")
                            }
                        }
                    } else {
                        $query = $query.Replace('#options#', "'$($db.name)'")
                    }

                    if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                        Write-Message -Message "Query to run: $query" -Level Verbose
                        $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
                        Write-Message -Message "$($results.Count)" -Level Verbose
                    }
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                }

                foreach ($row in $results) {
                    if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            Cmd          = $query.ToString()
                            Output       = $results
                        }
                    }
                }
            }
        }
    }
}