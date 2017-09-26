function Read-DbaXEventsFile {
 <#
	.SYNOPSIS
	Get a list of Extended Events Sessions

	.DESCRIPTION
	Retrieves a list of Extended Events Sessions

	.PARAMETER SqlInstance
	The SQL Instances that you're connecting to.

	.PARAMETER SqlCredential
	Credential object used to connect to the SQL Server as a different user

	.PARAMETER Session
	Only return specific sessions. This parameter is auto-populated.
		
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Memory
	Author: Klaas Vandenberghe ( @PowerDBAKlaas )
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Read-DbaXEventsFile

	.EXAMPLE
	Read-DbaXEventsFile -SqlInstance ServerA\sql987

	Returns a custom object with ComputerName, SQLInstance, Session, StartTime, Status and other properties.

	.EXAMPLE
	Get-DbaXEventsSession -SqlInstance sql2014 -Session deadlocks | Read-DbaXEventsFile
	
	Reads remote xevents 

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[object[]]$Path,
		[switch]$Silent
	)
	process {
		if ($Path.RemoteTargetFile) {
			$instance = [dbainstance]$Path.ComputerName
			
			if ($instance.IsLocal) {
				$Path = $Path.TargetFile
			}
			else {
				$Path = $Path.RemoteTargetFile
			}
		}
		
		foreach ($file in $path) {
			
			if (-not $Exact) {
				$file = $file.Replace('.xel', '*.xel')	
			}
			
			New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($file)
			#[pscustomobject]($d.actions | Select-Object Name, Value)
		}
	}
}