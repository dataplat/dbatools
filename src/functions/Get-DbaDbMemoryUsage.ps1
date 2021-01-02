function Get-DbaDbMemoryUsage {
    <#
    .SYNOPSIS
        Determine buffer pool usage by database.

    .DESCRIPTION
        This command can be utilized to determine which databases on a given instance are consuming buffer pool memory.

        This command is based on query provided by Aaron Bertrand.
        Reference: https://www.mssqltips.com/sqlservertip/2393/determine-sql-server-memory-use-by-database-and-object/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER IncludeSystemDb
        Switch to have the output include system database memory consumption.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Memory, Database
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMemoryUsage

    .EXAMPLE
        PS C:\> Get-DbaDbMemoryUsage -SqlInstance sqlserver2014a

        Returns the buffer pool consumption for all user databases

    .EXAMPLE
        PS C:\> Get-DbaDbMemoryUsage -SqlInstance sqlserver2014a -IncludeSystemDb

        Returns the buffer pool consumption for all user databases and system databases

    .EXAMPLE
        PS C:\> Get-DbaDbMemoryUsage -SqlInstance sql1 -IncludeSystemDb -Database tempdb

        Returns the buffer pool consumption for tempdb database only

    .EXAMPLE
        PS C:\> Get-DbaDbMemoryUsage -SqlInstance sql2 -IncludeSystemDb -Exclude 'master','model','msdb','ResourceDb'

        Returns the buffer pool consumption for all user databases and tempdb database
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipelineByPropertyName)]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystemDb,
        [switch]$EnableException
    )

    begin {
        $sql = "DECLARE @total_buffer INT;
            SELECT @total_buffer = cntr_value
            FROM sys.dm_os_performance_counters
            WHERE RTRIM([object_name]) LIKE '%Buffer Manager'
            AND counter_name = 'Database Pages';

            ;WITH src AS (
                SELECT database_id, page_type, db_buffer_pages = COUNT_BIG(*)
                FROM sys.dm_os_buffer_descriptors
                GROUP BY database_id, page_type
            )
            SELECT [DatabaseName] = CASE [database_id] WHEN 32767 THEN 'ResourceDb' ELSE DB_NAME([database_id]) END,
                page_type AS 'PageType',
                db_buffer_pages AS 'PageCount',
                (db_buffer_pages * 8)/1024 AS 'SizeMb',
                CAST(db_buffer_pages * 100.0 / @total_buffer AS FLOAT) AS 'PercentUsed'
            FROM src
            ORDER BY [DatabaseName];"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $results = $server.Query($sql)
            } catch {
                Stop-Function -Message "Issue collecting data" -Target $instance -ErrorRecord $_
            }
            foreach ($row in $results) {
                if (Test-Bound 'Database') {
                    if ($row.DatabaseName -notin $Database) { continue }
                }
                if (Test-Bound 'ExcludeDatabase') {
                    if ($row.DatabaseName -in $ExcludeDatabase) { continue }
                }
                if (Test-Bound -Not 'IncludeSystemDb') {
                    if ($row.DatabaseName -in 'master', 'model', 'msdb', 'tempdb', 'ResourceDb') { continue }
                }

                if ($row.PercentUsed -is [System.DBNull]) {
                    $percentUsed = 0
                } else {
                    $percentUsed = [Math]::Round($row.PercentUsed)
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $row.DatabaseName
                    PageType     = $row.PageType
                    PageCount    = [int]$row.PageCount
                    Size         = [DbaSize]$row.SizeMb * 1024
                    PercentUsed  = $percentUsed
                } | Select-DefaultView -ExcludeProperty 'PageCount'
            }
        }
    }
}