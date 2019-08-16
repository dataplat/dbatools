function Set-DbaDbIdentity {
    <#
    .SYNOPSIS
        Checks and updates the current identity value via DBCC CHECKIDENT

    .DESCRIPTION
        Use the command DBCC CHECKIDENT to check and if necessary update the current identity value of a table and return results
        Can update an individual table via the ReSeedValue and RESEED option of DBCC CHECKIDENT

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkident-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.
        Only one database should be specified when using a RESEED value

    .PARAMETER Table
        The table(s) for which to check the current identity value.
        Only one table should be specified when using a RESEED value

    .PARAMETER ReSeedValue
        The new reseed value to be used to set as the current identity value.

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
        https://dbatools.io/Set-DbaDbIdentity

    .EXAMPLE
        PS C:\> Set-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table 'Production.ScrapReason'

        Connects to AdventureWorks2014 on instance SqlServer2017 using Windows Authentication and runs the command DBCC CHECKIDENT('Production.ScrapReason') to return the current identity value.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> 'Sql1','Sql2/sqlexpress' | Set-DbaDbIdentity -SqlCredential $cred -Database AdventureWorks2014 -Table 'Production.ScrapReason'

        Connects to AdventureWorks2014 on instances Sql1 and Sql2/sqlexpress using sqladmin credential and runs the command DBCC CHECKIDENT('Production.ScrapReason') to return the current identity value.

    .EXAMPLE
        PS C:\> $query = "Select Schema_Name(t.schema_id) +'.' + t.name as TableName from sys.columns c INNER JOIN sys.tables t on t.object_id = c.object_id WHERE is_identity = 1"
        PS C:\> $IdentityTables = Invoke-DbaQuery -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Query $query
        PS C:\> foreach ($tbl in $IdentityTables) {
        PS C:\>    Set-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table $tbl.TableName
        PS C:\> }

        Checks the current identity value for all tables with an Identity in the AdventureWorks2014 database on the SQLServer2017 and, if it is needed, changes the identity value.


    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [int]$ReSeedValue,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC CHECKIDENT(#options#)")
    }
    process {
        if (Test-Bound -ParameterName ReSeedValue) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName Table)) {
                Stop-Function -Message "When using a reseed value you must specify a database and a table to execute against."
                return
            }

            if (($Database.Count -gt 1) -or ($Table.Count -gt 1)) {
                Stop-Function -Message "When using a reseed value you must specify a single database and a single table to execute against."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue
                }

                foreach ($tbl in $Table) {
                    try {
                        $query = $StringBuilder.ToString()
                        if (Test-Bound -Not -ParameterName ReSeedValue) {
                            $query = $query.Replace('#options#', "'$($tbl)'")
                        } else {
                            $query = $query.Replace('#options#', "'$($tbl)', RESEED, $($ReSeedValue)")
                        }

                        if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                            Write-Message -Message "Query to run: $query" -Level Verbose
                            $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                            if ($null -ne $results) {
                                $words = $results.Split(" ")
                                $identityValue = $words[6].Replace("'", "").Replace(",", "")
                                if (Test-Bound -Not -ParameterName ReSeedValue) {
                                    $columnValue = $words[10].Replace("'", "").Replace(".", "")
                                } else {
                                    $columnValue = ''
                                }

                            } else {
                                $identityValue = $null
                                $columnValue = $null
                            }
                        }
                    } catch {
                        Stop-Function -Message "Error running  $query against $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue
                    }
                    if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db.Name
                            Table         = $tbl
                            Cmd           = $query.ToString()
                            IdentityValue = $identityValue
                            ColumnValue   = $columnValue
                            Output        = $results
                        }
                    }
                }
            }
        }
    }
}