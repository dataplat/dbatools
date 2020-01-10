function Get-DbaSuspectPage {
    <#
    .SYNOPSIS
        Returns data that is stored in SQL for Suspect Pages on the specified SQL Server Instance

    .DESCRIPTION
        This function returns any records that were stored due to suspect pages in databases on a SQL Server Instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to return. If unspecified, all records will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Pages, DBCC
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

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
        foreach ($instance in $sqlinstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }

            $sql = "Select
            DB_NAME(database_id) as DBName,
            file_id,
            page_id,
            CASE event_type
            WHEN 1 THEN '823 or 824 or Torn Page'
            WHEN 2 THEN 'Bad Checksum'
            WHEN 3 THEN 'Torn Page'
            WHEN 4 THEN 'Restored'
            WHEN 5 THEN 'Repaired (DBCC)'
            WHEN 7 THEN 'Deallocated (DBCC)'
            END as EventType,
            error_count,
            last_update_date
            from msdb.dbo.suspect_pages"

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