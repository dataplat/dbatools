function Get-DbaTable {
    <#
.SYNOPSIS
Returns a summary of information on the tables

.DESCRIPTION
Shows table information around table row and data sizes and if it has any table type information.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a
collection and receive pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information

.PARAMETER Table
Define a specific table you would like to query. You can specify up to three-part name like db.sch.tbl.
If the object has special characters please wrap them in square brackets [ ].
This dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
The correct way to find table named 'First.Table' on schema 'dbo' is passing dbo.[First.Table]

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Database, Tables
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaTable

.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Database Test1
Return all tables in the Test1 database

.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Database MyDB -Table MyTable
Return only information on the table MyTable from the database MyDB

.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Table MyTable
Returns information on table called MyTable if it exists in any database on the server, under any schema

.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Table dbo.[First.Table]
Returns information on table called First.Table on schema dbo if it exists in any database on the server

.EXAMPLE
'localhost','localhost\namedinstance' | Get-DbaTable -Database DBA -Table Commandlog
Returns information on the CommandLog table in the DBA database on both instances localhost and the named instance localhost\namedinstance

#>
    [CmdletBinding()]
    param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [string[]]$Table,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        if ($Table) {
            $fqtns = @()
            foreach ($t in $Table) {
                $splitName = [regex]::Matches($t, "(\[.+?\])|([^\.]+)").Value
                $dotcount = $splitName.Count

                $splitDb = $Schema = $null

                switch ($dotcount) {
                    1 {
                        $tbl = $t
                    }
                    2 {
                        $schema = $splitName[0]
                        $tbl = $splitName[1]
                    }
                    3 {
                        $splitDb = $splitName[0]
                        $schema = $splitName[1]
                        $tbl = $splitName[2]
                    }
                    default {
                        Write-Message -Level Warning -Message "Please make sure that you are using up to three-part names. If your search value contains '.' character you must use [ ] to wrap the name. The value $t is not a valid name."
                        Continue
                    }
                }

                if ($splitDb -like "[[]*[]]") {
                    $splitDb = $splitDb.Substring(1, ($splitDb.Length - 2))
                }

                if ($schema -like "[[]*[]]") {
                    $schema = $schema.Substring(1, ($schema.Length - 2))
                }

                if ($tbl -like "[[]*[]]") {
                    $tbl = $tbl.Substring(1, ($tbl.Length - 2))
                }

                $fqtns += [PSCustomObject] @{
                    Database = $splitDb
                    Schema   = $Schema
                    Table    = $tbl
                }
            }
        }
    }

    process {
        foreach ($instance in $sqlinstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                #only look at online databases (Status equal normal)
                $dbs = $server.Databases | Where-Object IsAccessible

                #If IncludeSystemDBs is false, exclude systemdbs
                if (!$IncludeSystemDBs -and !$Database) {
                    $dbs = $dbs | Where-Object { !$_.IsSystemObject }
                }

                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name }
                }

                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
            catch {
                Stop-Function -Message "Unable to gather dbs for $instance" -Target $instance -Continue -ErrorRecord $_
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db"

                if ($fqtns) {
                    $tables = @()
                    foreach ($fqtn in $fqtns) {
                        # If the user specified a database in a three-part name, and it's not the
                        # database currently being processed, skip this table.
                        if ($fqtn.Database) {
                            if ($fqtn.Database -ne $db.Name) {
                                continue
                            }
                        }

                        $tbl = $db.tables | Where-Object { $_.Name -in $fqtn.Table -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }

                        if (-not $tbl) {
                            Write-Message -Level Verbose -Message "Could not find table $($fqtn.Table) in $db on $server"
                        }
                        $tables += $tbl
                    }
                }
                else {
                    $tables = $db.Tables
                }

                foreach ($sqltable in $tables) {
                    $sqltable | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    $sqltable | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    $sqltable | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    $sqltable | Add-Member -Force -MemberType NoteProperty -Name Database -Value $db.Name

                    $defaultprops = "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex", "IsFileTable", "IsMemoryOptimized", "IsPartitioned", "FullTextIndex", "ChangeTrackingEnabled"

                    Select-DefaultView -InputObject $sqltable -Property $defaultprops
                }
            }
        }
    }
}
