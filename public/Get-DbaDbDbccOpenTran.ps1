function Get-DbaDbDbccOpenTran {
    <#
    .SYNOPSIS
        Identifies the oldest active transactions in database transaction logs using DBCC OPENTRAN

    .DESCRIPTION
        Executes DBCC OPENTRAN against specified databases to identify long-running or problematic transactions that may be causing blocking, transaction log growth, or replication delays.

        This function helps DBAs troubleshoot performance issues by revealing the oldest active transaction and any distributed or replicated transactions within each database's transaction log. When transactions remain open for extended periods, they prevent log truncation and can cause cascading blocking issues throughout your SQL Server instance.

        The output includes detailed transaction information in structured PowerShell objects, making it easy to identify which transactions need attention. If no active transactions are found, the function clearly indicates this status for each database checked.

        This is particularly valuable when investigating sudden transaction log growth, diagnosing blocking chains, or troubleshooting replication latency issues where old transactions may be preventing log reader processes from advancing.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-opentran-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.
        The Name or Id of a database can be specified
        Database names must comply with the rules for identifiers.


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
        https://dbatools.io/Get-DbaDbDbccOpenTran

    .EXAMPLE
        PS C:\> Get-DbaDbDbccOpenTran -SqlInstance SQLServer2017

        Connects to instance SqlServer2017 using Windows Authentication and runs the command DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS against each database.

    .EXAMPLE
        PS C:\> Get-DbaDbDbccOpenTran -SqlInstance SQLServer2017 -Database CurrentDB

        Connects to instance SqlServer2017 using Windows Authentication and runs the command DBCC OPENTRAN(CurrentDB) WITH TABLERESULTS, NO_INFOMSGS against the CurrentDB database.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbDbccOpenTran -SqlCredential $cred

        Connects to instances Sql1 and Sql2/sqlexpress using sqladmin credential and runs the command DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS against each database.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC OPENTRAN(#options#) WITH TABLERESULTS, NO_INFOMSGS")
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
                    $query = $query.Replace('#options#', "'$($db.Name)'")

                    Write-Message -Message "Query to run: $query" -Level Verbose
                    $results = $server.Query($query)
                    Write-Message -Message "Finshed" -Level Verbose
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                }

                if ($null -eq $results) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        DatabaseId   = $db.Id
                        Cmd          = $query.ToString()
                        Output       = 'No active open transactions.'
                        Field        = $null
                        Data         = $null
                    }
                } else {
                    foreach ($row in $results) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            DatabaseId   = $db.Id
                            Cmd          = $query.ToString()
                            Output       = 'Oldest active transaction'
                            Field        = $row[0]
                            Data         = $row[1]
                        }
                    }
                }
            }
        }
    }
}