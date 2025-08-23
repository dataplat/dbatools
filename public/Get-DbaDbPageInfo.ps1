function Get-DbaDbPageInfo {
    <#
    .SYNOPSIS
        Retrieves detailed page allocation information from SQL Server databases for storage analysis and troubleshooting

    .DESCRIPTION
        This function queries the sys.dm_db_database_page_allocations dynamic management view to return detailed information about page allocation, including page type, free space percentage, allocation status, and mixed page allocation indicators.
        Use this when troubleshooting storage issues, analyzing space utilization patterns, or investigating page-level performance problems in your databases.
        Results can be filtered by specific databases, schemas, and tables to focus your analysis on problem areas.
        Requires SQL Server 2012 or higher as it depends on the sys.dm_db_database_page_allocations DMV.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for page allocation information. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases rather than scanning all databases on the instance.

    .PARAMETER Schema
        Limits the analysis to tables within specific schemas only. Multiple schema names can be provided.
        Helpful when troubleshooting page issues in specific application schemas or when you want to exclude system schemas from results.

    .PARAMETER Table
        Restricts page information retrieval to specific tables only. Can be combined with Schema parameter for precise targeting.
        Use this when investigating page allocation problems for known problematic tables or when performing focused storage analysis.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase, allowing you to chain commands together.
        This enables scenarios like getting databases from multiple instances and then analyzing their page information in a single pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Page
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbPageInfo

    .EXAMPLE
        PS C:\> Get-DbaDbPageInfo -SqlInstance sql2017

        Returns page information for all databases on sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbPageInfo -SqlInstance sql2017, sql2016 -Database testdb

        Returns page information for the testdb on sql2017 and sql2016

    .EXAMPLE
        PS C:\> $servers | Get-DbaDatabase -Database testdb | Get-DbaDbPageInfo

        Returns page information for the testdb on all $servers

    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, [Database] = DB_NAME(DB_ID()),
        ss.name AS [Schema], st.name AS [Table], dbpa.page_type_desc AS PageType,
                        dbpa.page_free_space_percent AS PageFreePercent,
                        IsAllocated =
                          CASE dbpa.is_allocated
                             WHEN 0 THEN 'False'
                             WHEN 1 THEN 'True'
                          END,
                        IsMixedPage =
                          CASE dbpa.is_mixed_page_allocation
                             WHEN 0 THEN 'False'
                             WHEN 1 THEN 'True'
                          END
                        FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS dbpa
                        INNER JOIN sys.tables AS st ON st.object_id = dbpa.object_id
                        INNER JOIN sys.schemas AS ss ON ss.schema_id = st.schema_id"

        if ($Schema) {
            $sql = "$sql WHERE ss.name IN ('$($Schema -join "','")')"
        }

        if ($Table) {
            if ($schema) {
                $sql = "$sql AND st.name IN ('$($Table -join "','")')"
            } else {
                $sql = "$sql WHERE st.name IN ('$($Table -join "','")')"
            }
        }
    }
    process {
        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
            } else {
                $InputObject += $server.Databases
            }
        }

        # Loop through each of databases
        foreach ($db in $InputObject) {
            # Revalidate the version of the server in case db is piped in
            try {
                if ($db.Parent.VersionMajor -ge 11) {
                    $db.Query($sql)
                } else {
                    Stop-Function -Message "Unsupported SQL Server version" -Target $db -Continue
                }
            } catch {
                Stop-Function -Message "Something went wrong executing the query" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}