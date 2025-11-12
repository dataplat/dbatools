function Get-DbaSuspectPage {
    <#
    .SYNOPSIS
        Retrieves suspect page records from msdb database for corruption detection and analysis

    .DESCRIPTION
        Queries the msdb.dbo.suspect_pages table to identify database pages that have experienced corruption events such as checksum failures, torn pages, or I/O errors. SQL Server automatically logs corrupt pages to this system table when encountered during read operations, making this function essential for proactive corruption monitoring and troubleshooting. Returns detailed information including the specific database, file, page location, error type, occurrence count, and last detection date to help DBAs prioritize remediation efforts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Filters suspect page results to a specific database name. When omitted, returns suspect pages from all databases on the instance.
        Use this when investigating corruption issues in a particular database or when you need to focus troubleshooting efforts on a single database.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Pages, DBCC
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSuspectPage

    .EXAMPLE
        PS C:\> Get-DbaSuspectPage -SqlInstance sql2016

        Retrieve any records stored for Suspect Pages on the sql2016 SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaSuspectPage -SqlInstance sql2016 -Database Test

        Retrieve any records stored for Suspect Pages on the sql2016 SQL Server and the Test database only.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object]$Database,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql = "SELECT
            DB_NAME(database_id) AS DBName,
            file_id,
            page_id,
            CASE event_type
            WHEN 1 THEN '823 or 824'
            WHEN 2 THEN 'Bad Checksum'
            WHEN 3 THEN 'Torn Page'
            WHEN 4 THEN 'Restored'
            WHEN 5 THEN 'Repaired (DBCC)'
            WHEN 7 THEN 'Deallocated (DBCC)'
            END AS EventType,
            error_count,
            last_update_date
            FROM msdb.dbo.suspect_pages"

            try {
                $results = $server.Query($sql)
            } catch {
                Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
            }

            if ($Database) {
                $results = $results | Where-Object DBName -EQ $Database
            }

        }
        foreach ($row in $results) {
            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Database       = $row.DBName
                FileId         = $row.file_id
                PageId         = $row.page_id
                EventType      = $row.EventType
                ErrorCount     = $row.error_count
                LastUpdateDate = $row.last_update_date
            }
        }
    }
}