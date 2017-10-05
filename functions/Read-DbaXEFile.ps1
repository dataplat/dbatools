function Read-DbaXEFile {
 <#
	.SYNOPSIS
	Read XEvents from a xel or xem file

	.DESCRIPTION
	Read XEvents from a xel or xem file. 
	
	.PARAMETER Path
	The path to the file. This is relative to the computer executing the command. UNC paths supported.
	
	.PARAMETER Exact
	By default, this command will add a wildcard to the Path because Eventing uses the file name as a template and adds characters. Use this to skip the addition of the wildcard.
		
	.PARAMETER Raw
	Returns the Microsoft.SqlServer.XEvent.Linq.PublishedEvent enumeration object
	
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Xevent
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Read-DbaXEFile

	.EXAMPLE
	Read-DbaXEFile -SqlInstance ServerA\sql987 -Path C:\temp\deadocks.xel

	Returns events

	.EXAMPLE
	Get-DbaXESession -SqlInstance sql2014 -Session deadlocks | Read-DbaXEFile
	
	Reads remote xevents by acccessing the file over the admin UNC share

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[object[]]$Path,
		[switch]$Exact,
		[switch]$Raw,
		[switch]$Silent
	)
	process {
		foreach ($file in $path) {
			
			if ($file -is [System.String]) {
				$currentfile = $file
			}
			else {
				if ($file.TargetFile.Length -eq 0) { continue }
				
				$instance = [dbainstance]$file.ComputerName
				
				if ($instance.IsLocalHost) {
					$currentfile = $file.TargetFile
				}
				else {
					$currentfile = $file.RemoteTargetFile
				}
			}
			
			if (-not $Exact) {
				$currentfile = $currentfile.Replace('.xel', '*.xel')
				$currentfile = $currentfile.Replace('.xem', '*.xem')
			}
			
			$accessible = Test-Path -Path $currentfile
			$whoami = whoami
			
			if (-not $accessible) {
				if ($file.Status -eq "Stopped") { continue }
				Stop-Function -Continue -Message "$currentfile cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?"
			}
			
			if ($raw) {
				New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile)
			}
			else {
				# Make it selectable, otherwise it's a weird enumeration
				foreach ($row in (New-Object Microsoft.SqlServer.XEvent.Linq.QueryableXEventData($currentfile))) {
					Select-DefaultView -InputObject $row -Property Name, Timestamp, Fields, Actions
				}
			}
		}
	}
}