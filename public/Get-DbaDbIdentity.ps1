function Get-DbaDbIdentity {
    <#
    .SYNOPSIS
        Retrieves current identity values from tables without reseeding using DBCC CHECKIDENT

    .DESCRIPTION
        Executes DBCC CHECKIDENT with the NORESEED option to retrieve current identity seed and column values from specified tables without modifying anything. This provides a safe way to inspect identity column status across multiple tables, databases, and instances simultaneously.

        DBAs use this when troubleshooting identity gaps, planning bulk operations, or auditing identity column usage before performing maintenance tasks. Unlike running DBCC CHECKIDENT manually, this command structures the output into readable PowerShell objects that show both the current identity value and the actual highest value in the column.

        The NORESEED option ensures no changes are made to your tables - it's purely informational. The function parses the DBCC output to extract specific identity metrics, making it ideal for scripted monitoring and reporting workflows.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkident-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for identity column values. If not specified, all accessible databases on the instance are processed.
        Use this to focus on specific databases when you don't need identity information from every database on the server.

    .PARAMETER Table
        Specifies the table names to check for current identity seed and column values. Accepts schema-qualified names like 'Production.ScrapReason'.
        This parameter is required since DBCC CHECKIDENT must target specific tables. Use a query against sys.columns to find all tables with identity columns if needed.

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
        https://dbatools.io/Get-DbaDbIdentity

    .EXAMPLE
        PS C:\> Get-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table 'Production.ScrapReason'

        Connects to AdventureWorks2014 on instance SqlServer2017 using Windows Authentication and runs the command DBCC CHECKIDENT('Production.ScrapReason', NORESEED) to return the current identity value.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbIdentity -SqlCredential $cred -Database AdventureWorks2014 -Table 'Production.ScrapReason'

        Connects to AdventureWorks2014 on instances Sql1 and Sql2/sqlexpress using sqladmin credential and runs the command DBCC CHECKIDENT('Production.ScrapReason', NORESEED) to return the current identity value.

    .EXAMPLE
        PS C:\> $query = "SELECT QUOTENAME(SCHEMA_NAME(t.schema_id)) +'.' + QUOTENAME(t.name) AS TableName FROM sys.columns c INNER JOIN sys.tables t ON t.object_id = c.object_id WHERE is_identity = 1 AND is_memory_optimized = 0"
        PS C:\> $IdentityTables = Invoke-DbaQuery -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Query $query -As SingleValue
        PS C:\> Get-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table $IdentityTables

        Checks the current identity value for all non memory optimized tables with an Identity in the AdventureWorks2014 database on the SQLServer2017 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC CHECKIDENT(#options#, NORESEED)")
    }
    process {
        if (Test-Bound -Not -ParameterName Table) {
            Stop-Function -Message "You must specify a table to execute against using -Table"
            return
        }
        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                        $query = $query.Replace('#options#', "'$($tbl)'")

                        if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                            Write-Message -Message "Query to run: $query" -Level Verbose
                            $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                            if ($null -ne $results) {
                                $words = $results.Split(" ")
                                $identityValue = $words[6].Replace("'", "").Replace(",", "")
                                $columnValue = $words[10].Replace("'", "").Replace(".", "")
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