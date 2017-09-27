function Read-DbaXEventsFile {
 <#
	.SYNOPSIS
	Read XEvents from a xel or xem file

	.DESCRIPTION
	Read XEvents from a xel or xem file

	.PARAMETER Path
	The path to the file. This is relative to the computer executing the command.
		
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Xevent
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Read-DbaXEventsFile

	.EXAMPLE
	Read-DbaXEventsFile -SqlInstance ServerA\sql987 -Path C:\temp\deadocks.xel

	Returns events

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
				$file = $file.Replace('.xem', '*.xem')
			}
			
			New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($file)
			#[pscustomobject]($d.actions | Select-Object Name, Value)
		}
	}
}