function Find-DbaStoredProcedure {
    <#
    .SYNOPSIS
        Searches stored procedure definitions for specific text patterns or regex expressions across SQL Server databases.

    .DESCRIPTION
        Searches through stored procedure source code to find specific strings, patterns, or regex expressions within the procedure definitions. This is particularly useful for finding hardcoded values, deprecated function calls, security vulnerabilities, or specific business logic across your database environment. The function examines the actual T-SQL code stored in sys.sql_modules and can search across multiple databases simultaneously. Results include the matching line numbers and context, making it easy to locate exactly where patterns appear within each procedure. You can scope searches to specific databases and choose whether to include system stored procedures and system databases in the search.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for stored procedures containing the pattern. Accepts database names and supports wildcards.
        When omitted, searches all user databases on the instance. Use this to focus searches on specific databases when you know where procedures are located.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the stored procedure search. Accepts database names and supports wildcards.
        Use this when you want to search most databases but exclude specific ones like test environments or databases with sensitive procedures.

    .PARAMETER Pattern
        Specifies the text pattern or regular expression to search for within stored procedure definitions. Supports full regex syntax for complex pattern matching.
        Use this to find hardcoded values, deprecated functions, security vulnerabilities, or specific business logic across procedure source code.

    .PARAMETER IncludeSystemObjects
        Includes system stored procedures (those shipped with SQL Server) in the search results. By default, only user-created procedures are searched.
        Use this when investigating system procedures or when patterns might exist in Microsoft-provided code. Warning: this significantly slows performance when searching multiple databases.

    .PARAMETER IncludeSystemDatabases
        Includes system databases (master, model, msdb, tempdb) in the search scope. By default, only user databases are searched.
        Use this when investigating system procedures or when your pattern might exist in maintenance scripts stored in system databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: StoredProcedure, Proc, Lookup
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaStoredProcedure

    .EXAMPLE
        PS C:\> Find-DbaStoredProcedure -SqlInstance DEV01 -Pattern whatever

        Searches all user databases stored procedures for "whatever" in the text body

    .EXAMPLE
        PS C:\> Find-DbaStoredProcedure -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

        Searches all databases for all stored procedures that contain a valid email pattern in the text body

    .EXAMPLE
        PS C:\> Find-DbaStoredProcedure -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

        Searches in "mydb" database stored procedures for "some string" in the text body

    .EXAMPLE
        PS C:\> Find-DbaStoredProcedure -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

        Searches in "mydb" database stored procedures for "runtime" in the text body

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory)]
        [string]$Pattern,
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        $sql =
        "SELECT OBJECT_SCHEMA_NAME(p.object_id) AS ProcSchema, p.name, m.definition AS TextBody
          FROM sys.sql_modules AS m
           INNER JOIN sys.procedures AS p
            ON m.object_id = p.object_id"

        if (!$IncludeSystemObjects) { $sql = "$sql WHERE p.is_ms_shipped = 0;" }

        $everyserverspcount = 0
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            } else {
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

                Write-Message -Level Debug -Message $sql
                $rows = $db.ExecuteWithResults($sql).Tables.Rows
                $sproccount = 0

                foreach ($row in $rows) {
                    $totalcount++; $sproccount++; $everyserverspcount++

                    $procSchema = $row.ProcSchema
                    $proc = $row.Name

                    Write-Message -Level Verbose -Message "Looking in stored procedure: $procSchema.$proc textBody for $pattern"
                    if ($row.TextBody -match $Pattern) {
                        $sp = $db.StoredProcedures | Where-Object { $_.Schema -eq $procSchema -and $_.Name -eq $proc }

                        $StoredProcedureText = $row.TextBody
                        $splitOn = [string[]]@("`r`n", "`r", "`n" )
                        $spTextFound = $StoredProcedureText.Split( $splitOn , [System.StringSplitOptions]::None ) |
                            Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                        [PSCustomObject]@{
                            ComputerName             = $server.ComputerName
                            SqlInstance              = $server.ServiceName
                            Database                 = $db.Name
                            DatabaseId               = $db.ID
                            Schema                   = $sp.Schema
                            Name                     = $sp.Name
                            Owner                    = $sp.Owner
                            IsSystemObject           = $sp.IsSystemObject
                            CreateDate               = $sp.CreateDate
                            LastModified             = $sp.DateLastModified
                            StoredProcedureTextFound = $spTextFound -join [System.Environment]::NewLine
                            StoredProcedure          = $sp
                            StoredProcedureFullText  = $StoredProcedureText
                        } | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
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