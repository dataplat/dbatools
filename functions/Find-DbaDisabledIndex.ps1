function Find-DbaDisabledIndex {
    <#
        .SYNOPSIS
            Find Disabled indexes

        .DESCRIPTION
            This command will help you to find disabled indexes on a database or a list of databases.

        .PARAMETER SqlInstance
            The SQL Server you want to check for disabled indexes.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER NoClobber
            If this switch is enabled, the output file will not be overwritten.

        .PARAMETER Append
            If this switch is enabled, content will be appended to the output file.

            .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Indexes
            Author: Jason Squires, sqlnotnull.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Find-DbadisabledIndex

        .EXAMPLE
            Find-DbadisabledIndex -SqlInstance sql2005

            Generates the SQL statements to drop the selected disabled indexes on server "sql2005".

        .EXAMPLE
            Find-DbadisabledIndex -SqlInstance sqlserver2016 -SqlCredential $cred

            Generates the SQL statements to drop the selected disabled indexes on server "sqlserver2016", using SQL Authentication to connect to the database.

        .EXAMPLE
            Find-DbadisabledIndex -SqlInstance sqlserver2016 -Database db1, db2

            Generates the SQL Statement to drop selected indexes in databases db1 & db2 on server "sqlserver2016".

        .EXAMPLE
            Find-DbadisabledIndex -SqlInstance sqlserver2016

            Generates the SQL statements to drop selected indexes on all user databases.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$NoClobber,
        [switch]$Append,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $sql = "
        SELECT DB_NAME() AS 'DatabaseName'
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
        WHERE i.is_disabled = 1"
    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential  -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $databases = $server.Databases | Where-Object Name -in $database
            }
            else {
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
                            }
                            else {
                                Write-Message -Level Verbose -Message "No Disabled indexes found!"
                            }
                        }
                    }
                    catch {
                        Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -InnerErrorRecord $_ -Target $db
                    }
                }
            }
            else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-SqlDisabledIndex
    }
}