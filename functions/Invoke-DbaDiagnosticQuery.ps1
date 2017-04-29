function Invoke-DbaDiagnosticQuery {
<#
.SYNOPSIS 
Invoke-DbaDiagnosticQuery runs the scripts provided by Glenn Berry's DMV scripts on specified servers.

.DESCRIPTION
This is the main function of the Sql Server Diagnostic Queries related functions in dbatools. 
The diagnostic queries are developed and maintained by Glenn Berry and they can be found here along with a lot of documentation:
http://www.sqlskills.com/blogs/glenn/category/dmv-queries/

The most recent version of the diagnostic queries are included in the dbatools module. 
But it is possible to download a newer set or a specific version to an alternative location and parse and run those scripts.
It will run all or a selection of those scripts on one or multiple servers and return the result as a PowerShell Object

.PARAMETER SqlInstance
The target SQL Server. Can be either a string or SMO server.
	
.PARAMETER Path
Alternate path for the diagnostic scripts
	
.PARAMETER UseSelectionHelper
Provides a gridview with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified. 
	
.PARAMETER InstanceOnly
Should maybe be Scope with the choices Instance and Database

.PARAMETER DatabaseSpecific
Specifies the path to the output files. 
	
.PARAMETER Silent
Use this switch to disable any kind of verbose messages or progress bars

.NOTES
Author: André Kamman (@AndreKamman), http://clouddba.io

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Invoke-DbaDiagnosticQuery


.EXAMPLE   
Invoke-DbaDiagnosticQuery -SqlInstance sql2016 -UseSelectionHelper

Provides a gridview with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified. 

#>
	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[System.IO.FileInfo]$Path,
		[string[]]$QueryName,
		[switch]$UseSelectionHelper,
		[switch]$InstanceOnly,
		[switch]$DatabaseSpecific,
		[switch]$Silent
	)
	
	begin {
		
		Write-Message -Level Verbose -Message "Interpreting DMV Script Collections"
		
		if (!$path) {
			$module = Get-Module -Name dbatools
			$base = $module.ModuleBase
			$path = "$base\bin\diagnosticquery"
		}
		
		$scriptversions = @()
		
		$scriptfiles = Get-ChildItem "$Path\SQLServerDiagnosticQueries_*_*.sql"
		
		if (!$scriptfiles) {
			Write-Verbose "No files, download?"
			Save-DbaDiagnosticQueryScript -Path $Path
			
			$scriptfiles = Get-ChildItem "$Path\SQLServerDiagnosticQueries_*_*.sql"
			if (!$scriptfiles) {
				Stop-Function -Message "Unable to download scripts, do you have an internet connection? $_" -InnerErrorRecord $_
			}
		}
		
		[int[]]$filesort = $null
		
		foreach ($file in $scriptfiles) {
			$filesort += $file.BaseName.Split("_")[2]
		}
		
		$currentdate = $filesort | Sort-Object -Descending | Select-Object -First 1
		
		foreach ($file in $scriptfiles) {
			if ($file.BaseName.Split("_")[2] -eq $currentdate) {
				$script = Invoke-DbaDiagnosticQueryScriptParser -filename $file.fullname
				
				$newscript = [pscustomobject]@{
					Version = $file.Basename.Split("_")[1]
					Script = $script
				}
				$scriptversions += $newscript
			}
		}
	}
	process {
		
		try {
			Write-Message -Level Verbose -Message "Connecting to $sqlinstance"
			$server = Connect-SqlServer -SqlServer $sqlinstance -SqlCredential $sqlcredential
		}
		catch {
			Stop-Function -Message "Failed to connect to $instance : $($_.Exception.Message)" -Continue -Target $instance -InnerErrorRecord $_
		}
		
		$out = "Collecting diagnostic query Data from Server: $SqlInstance"
		Write-Message -Level Verbose -Message $out
		
		if (!$Silent) { Write-Progress -Id 0 -Activity "Running Scripts on SQL Server"tatus ("Instance {0} of {1}" -f $servercounter, $sqlservers.count) -CurrentOperation $SqlInstance -PercentComplete (($servercounter / $SqlServers.count) * 100) }
		
		if ($server.VersionMinor -eq 50) {
			$version = "2008R2"
		}
		else {
			$version = switch ($server.VersionMajor) {
				9 { "2005" }
				10 { "2008" }
				11 { "2012" }
				12 { "2014" }
				13 { "2016" }
				14 { "2017" }
			}
		}
		
		if (!$InstanceOnly) {
			$databases = Invoke-Sqlcmd2 -ServerInstance $SqlInstance -Database master -Query "Select Name from sys.databases where name not in ('master', 'model', 'msdb', 'tempdb')"
		}
		
		$script = $scriptversions | Where-Object -Property Version -eq $version | Select-Object -ExpandProperty Script
		
		if ($null -eq $first) { $first = $true }
		if ($UseSelectionHelper -and $first) {
			$QueryName = Invoke-DbaDiagnosticQueriesSelectionHelper $script
			$first = $false
		}
		
		if (!$instanceonly -and !$DatabaseSpecific -and !$QueryName) {
			$scriptcount = $script.count
		}
		elseif ($InstanceOnly) {
			$scriptcount = ($script | Where-Object DatabaseSpecific -eq $false).count
		}
		elseif ($DatabaseSpecific) {
			$scriptcount = ($script | Where-Object DatabaseSpecific).count
		}
		elseif ($QueryName.Count -ne 0) {
			$scriptcount = $QueryName.Count
		}
		
		foreach ($scriptpart in $script) {
			if (($QueryName.Count -ne 0) -and ($QueryName -notcontains $scriptpart.QueryName)) { continue }
			if (!$scriptpart.DatabaseSpecific -and !$DatabaseSpecific) {
				if ($PSCmdlet.ShouldProcess($SqlInstance, $scriptpart.QueryName)) {
					
					if (!$Silent) {
						Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic queries Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100)
					}
					try {
						$result = Invoke-Sqlcmd2 -ServerInstance $SqlInstance -Database master -Query $($scriptpart.Text) -ErrorAction Stop
						if (!$result) {
							$result = [pscustomobject]@{
								Number = $scriptpart.Number
								Name = $scriptpart.Name
								Message = "Empty Result for this Query"
							}
							Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.Number, $scriptpart.Name, $scriptpart.Description)
						}
					}
					catch {
						Write-Message -Level Verbose -Message ('Some error has occured on Server: {0} - Script: {1}, result will not be saved' -f $SqlInstance, $Scriptpart.name)
					}
					if ($result) {
						
						$clixmlresult = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
						[pscustomobject]@{
							Number = $scriptpart.Number
							Name = $scriptpart.QueryName
							Description = $scriptpart.Description
							DatabaseSpecific = $scriptpart.DatabaseSpecific
							DatabaseName = $null
							Result = $clixmlresult
						}
					}
				}
			}
			elseif ($scriptpart.DatabaseSpecific -and !$InstanceOnly) {
				foreach ($database in $databases) {
					if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $SqlInstance, $database.name), $scriptpart.QueryName)) {
						if (!$Silent) { Write-Progress -Id 0 -Activity "Running diagnostic queries on SQL Server" -Status ("Instance {0} of {1}" -f $servercounter, $sqlservers.count) -CurrentOperation $SqlInstance -PercentComplete (($servercounter / $SqlServers.count) * 100) }
						if (!$Silent) { Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic query Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100) }
						try {
							$result = Invoke-Sqlcmd2 -ServerInstance $SqlInstance -Database $database.Name -Query $scriptpart.Text -ErrorAction Stop
							if (!$result) {
								$result = [pscustomobject]@{
									Number = $scriptpart.Number
									Name = $scriptpart.Name
									Message = "Empty Result for this Query"
								}
								Write-Message -Level Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.Number, $scriptpart.Name, $scriptpart.Description)
							}
						}
						catch {
							Write-Message -Level Verbose -Message ('Some error has occured on Server: {0} - Script: {1} - Database: {2}, result will not be saved' -f $SqlInstance, $scriptpart.name, $database.Name)
						}
						
						[pscustomobject]@{
							Number = $scriptpart.Number
							Name = $scriptpart.QueryName
							Description = $scriptpart.Description
							DatabaseSpecific = $scriptpart.DatabaseSpecific
							DatabaseName = $database.name
							Result = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
						}
					}
				}
			}
		}
		Write-Message -Level Output -Message "Don't judge, I'm not done ;) Looking into unwrapping the result and seeing what that's like"
	}
}
