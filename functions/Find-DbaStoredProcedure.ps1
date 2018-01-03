function Find-DbaStoredProcedure {
<#
.SYNOPSIS
Returns all stored procedures that contain a specific case-insensitive string or regex pattern.

.DESCRIPTION
This function can either run against specific databases or all databases searching all user or user and system stored procedures.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER Pattern
String pattern that you want to search for in the stored procedure textbody

.PARAMETER IncludeSystemObjects
By default, system stored procedures are ignored but you can include them within the search using this parameter.

Warning - this will likely make it super slow if you run it on all databases.

.PARAMETER IncludeSystemDatabases
By default system databases are ignored but you can include them within the search using this parameter

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Find-DbaStoredProcedure

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance DEV01 -Pattern whatever

Searches all user databases stored procedures for "whatever" in the textbody

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

Searches all databases for all stored procedures that contain a valid email pattern in the textbody

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

Searches in "mydb" database stored procedures for "some string" in the textbody

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

Searches in "mydb" database stored procedures for "runtime" in the textbody

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory = $true)]
        [string]$Pattern,
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $sql = "SELECT OBJECT_SCHEMA_NAME(p.object_id) as ProcSchema, p.name, m.definition as TextBody FROM sys.sql_modules m, sys.procedures p WHERE m.object_id = p.object_id"
        if (!$IncludeSystemObjects) { $sql = "$sql AND p.is_ms_shipped = 0" }
        $everyserverspcount = 0
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $Instance"
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            }
            catch {
                Write-Message -Level Warning -Message "Failed to connect to: $Instance"
                continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            }
            else {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            $totalcount = 0
            $dbcount = $dbs.count
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Searching on database $db"

                # If system objects aren't needed, find stored procedure text using SQL
                # This prevents SMO from having to enumerate

                if (!$IncludeSystemObjects) {
                    Write-Message -Level Debug -Message $sql
                    $rows = $db.ExecuteWithResults($sql).Tables.Rows
                    $sproccount = 0

                    foreach ($row in $rows) {
                        $totalcount++; $sproccount++; $everyserverspcount++

                        $procSchema = $row.ProcSchema
                        $proc = $row.Name

                        Write-Message -Level Verbose -Message "Looking in stored procedure: $procSchema.$proc textBody for $pattern"
                        if ($row.TextBody -match $Pattern) {
                            $sp = $db.StoredProcedures | Where-Object{$_.Schema -eq $procSchema -and $_.Name -eq $proc}

                            $StoredProcedureText = $sp.TextBody.split("`n")
                            $spTextFound = $StoredProcedureText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                            [PSCustomObject]@{
                                ComputerName             = $server.NetName
                                SqlInstance              = $server.ServiceName
                                Database                 = $db.Name
                                Schema                   = $sp.Schema
                                Name                     = $sp.Name
                                Owner                    = $sp.Owner
                                IsSystemObject           = $sp.IsSystemObject
                                CreateDate               = $sp.CreateDate
                                LastModified             = $sp.DateLastModified
                                StoredProcedureTextFound = $spTextFound -join "`n"
                                StoredProcedure          = $sp
                                StoredProcedureFullText  = $sp.TextBody
                            } | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
                        }
                    }
                }
                else {
                    $storedprocedures = $db.StoredProcedures

                    foreach ($sp in $storedprocedures) {
                        $totalcount++; $sproccount++; $everyserverspcount++

                        $procSchema = $sp.Schema
                        $proc = $sp.Name

                        Write-Message -Level Verbose -Message "Looking in stored procedure $procSchema.$proc textBody for $pattern"
                        if ($sp.TextBody -match $Pattern) {

                            $StoredProcedureText = $sp.TextBody.split("`n")
                            $spTextFound = $StoredProcedureText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                            [PSCustomObject]@{
                                ComputerName             = $server.NetName
                                SqlInstance              = $server.ServiceName
                                Database                 = $db.Name
                                Schema                   = $sp.Schema
                                Name                     = $sp.Name
                                Owner                    = $sp.Owner
                                IsSystemObject           = $sp.IsSystemObject
                                CreateDate               = $sp.CreateDate
                                LastModified             = $sp.DateLastModified
                                StoredProcedureTextFound = $spTextFound -join "`n"
                                StoredProcedure          = $sp
                                StoredProcedureFullText  = $sp.TextBody
                            } | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
                        }
                    }
                }
                Write-Message -Level Verbose -Message "Evaluated $sproccount stored procedures in $db"
            }
            Write-Message -Level Verbose -Message "Evaluated $totalcount total stored procedures in $dbcount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Evaluated $everyserverspcount total stored procedures"
    }
}
