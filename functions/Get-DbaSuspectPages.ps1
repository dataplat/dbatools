function Get-DbaSuspectPages {
	<#
.SYNOPSIS
Returns data that is stored in SQL for Suspect Pages on the specied SQL Server Instance

.DESCRIPTION
This function returns any records that were stored due to suspect pages in databases on a SQL Server Instance.

.PARAMETER SqlInstance
A SQL Server instance to connect to

.PARAMETER SqlCredential
A credential to use to conect to the SQL Instance rather than using Windows Authentication

.PARAMETER Database
The database to return. If unspecified, all records will be returned.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: Pages, DBCC
Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaSuspectPages -SqlInstance sql2016 

Retrieve any records stored for Suspect Pages on the sql2016 SQL Server.

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[object[]]$Database,
        [PSCredential]$SqlCredential,
		[switch]$Silent
	)
	
	process {
		
		foreach ($instance in $sqlinstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
				$server.Query($sql) 
			}
			catch {
				Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_
			}
			
			if ($Database) {
				$results = $results | Where-Object { $_.Name -EQ $Database }
			}

			foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                  ComputerName   = $server.NetName
                  InstanceName   = $server.ServiceName
                  SqlInstance    = $server.DomainInstanceName
                  DBName         = $row.DBName
                  FileId         = $row.file_id
                  PageId         = $row.page_id
                  EventType      = $row.EventType
                  ErrorCount     = $row.error_count
                  LastUpdateDate = $row.last_update_date
				} | Select-DefaultView 
			}
		}   
    }
}
