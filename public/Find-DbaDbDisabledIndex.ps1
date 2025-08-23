function Find-DbaDbDisabledIndex {
    <#
    .SYNOPSIS
        Identifies disabled indexes across SQL Server databases

    .DESCRIPTION
        Scans SQL Server databases to locate indexes that have been disabled, returning detailed information including database, schema, table, and index names. Disabled indexes consume storage space but aren't maintained during data modifications, making them candidates for cleanup or re-enabling. This is useful for database maintenance, performance troubleshooting, and identifying indexes that were disabled during bulk operations but never re-enabled.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for disabled indexes. Accepts multiple database names and supports wildcards.
        When not specified, all accessible user databases on the instance will be scanned.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the disabled index scan. Useful when you want to scan most databases but skip certain ones like staging or temp databases.
        Accepts multiple database names to exclude from the operation.

    .PARAMETER NoClobber
        Prevents overwriting existing output files when used with file export functionality.
        Note: This parameter is currently not implemented in the function logic.

    .PARAMETER Append
        Appends results to existing output files instead of overwriting them when used with file export functionality.
        Note: This parameter is currently not implemented in the function logic.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Index, Lookup
        Author: Jason Squires, sqlnotnull.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbDisabledIndex

    .EXAMPLE
        PS C:\> Find-DbaDbDisabledIndex -SqlInstance sql2005

        Generates the SQL statements to drop the selected disabled indexes on server "sql2005".

    .EXAMPLE
        PS C:\> Find-DbaDbDisabledIndex -SqlInstance sqlserver2016 -SqlCredential $cred

        Generates the SQL statements to drop the selected disabled indexes on server "sqlserver2016", using SQL Authentication to connect to the database.

    .EXAMPLE
        PS C:\> Find-DbaDbDisabledIndex -SqlInstance sqlserver2016 -Database db1, db2

        Generates the SQL Statement to drop selected indexes in databases db1 & db2 on server "sqlserver2016".

    .EXAMPLE
        PS C:\> Find-DbaDbDisabledIndex -SqlInstance sqlserver2016

        Generates the SQL statements to drop selected indexes on all user databases.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )

    begin {
        $sql = "
        SELECT DB_NAME() AS 'DatabaseName'
        ,d.database_id AS DatabaseId
        ,s.name AS 'SchemaName'
        ,t.name AS 'TableName'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id as 'IndexId'
        ,i.type_desc as 'TypeDesc'
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        JOIN sys.databases d
            ON d.name = DB_NAME()
        WHERE i.is_disabled = 1"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential  -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $databases = $server.Databases | Where-Object Name -in $database
            } else {
                $databases = $server.Databases | Where-Object IsAccessible -eq $true
            }

            if ($databases.Count -gt 0) {
                foreach ($db in $databases.name) {

                    if ($ExcludeDatabase -contains $db -or $null -eq $server.Databases[$db]) {
                        continue
                    }

                    try {
                        if ($PSCmdlet.ShouldProcess($db, "Getting disabled indexes")) {
                            Write-Message -Level Verbose -Message "Getting indexes from database '$db'."
                            Write-Message -Level Debug -Message "SQL Statement: $sql"
                            $disabledIndex = $server.Databases[$db].ExecuteWithResults($sql)

                            if ($disabledIndex.Tables[0].Rows.Count -gt 0) {
                                $results = $disabledIndex.Tables[0];
                                if ($results.Count -gt 0 -or !([string]::IsNullOrEmpty($results))) {
                                    foreach ($index in $results) {
                                        $index
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No Disabled indexes found"
                            }
                        }
                    } catch {
                        Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -InnerErrorRecord $_ -Target $db
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
}