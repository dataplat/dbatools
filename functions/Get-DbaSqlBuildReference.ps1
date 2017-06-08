Function Get-DbaSqlBuildReference
{
<#
.SYNOPSIS
Returns SQL Server Build infos on a SQL instance

.DESCRIPTION
Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
It also includes End Of Support dates as specified on Microsoft Lifecycle Policy

.PARAMETER Build
Instead of connecting to a real instance, pass a string identifying the build to get the info back.
	
.PARAMETER SqlInstance
Optionally, an SQL Server SMO object can be passed to the command to be parsed.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Author: niphlod
Tags: SqlBuild

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaSqlBuildReference

.EXAMPLE
Get-DbaSqlBuildReference -Build "12.00.4502"

Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

.EXAMPLE
Get-DbaSqlBuildReference -Build "12.0.4502","10.50.4260"

Returns information builds identified by these versions strings

.EXAMPLE
Get-SqlRegisteredServerName -SqlServer sqlserver2014a | Foreach-Object { Connect-DbaSqlServer -SqlServer $_ } | Get-DbaSqlBuildReference

Integrate with other commandlets to have builds checked for all your registered servers on sqlserver2014a

#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	Param (
		[string[]]$Build,
		[Parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[Microsoft.SqlServer.Management.Smo.Server[]]$SqlInstance,
		[switch]$Silent
	)

	BEGIN {
		function Find-DbaSqlBuildReferenceIndex {
			[CmdletBinding()]
			Param()
			$orig_idxfile = "$moduledirectory\bin\dbatools-buildref-index.json"
			$DbatoolsData = Get-DbaConfigValue -Name 'Path.DbatoolsData'
			$writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"
			if (!(Test-Path $orig_idxfile)) {
				Write-Message -Message "Unable to read local file" -Warning -Silent $Silent
			} else {
				if(!(Test-Path $writable_idxfile)) {
					Copy-Item $orig_idxfile $writable_idxfile
				}
				return (Get-Content -Raw $writable_idxfile)
			}
		}

		function Get-DbaSqlBuildReferenceIndex {
			[CmdletBinding()]
			Param()
			return Find-DbaSqlBuildReferenceIndex | ConvertFrom-Json
		}

		function Compare-DbaSqlBuildGreater {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			[OutputType([bool])]
			Param([string]$firstref, [string]$secondref)
			$first = $firstref.split('.') | Foreach-Object { [convert]::ToInt32($_) }
			$second = $secondref.split('.') | Foreach-Object { [convert]::ToInt32($_) }
			$x = 0
			while($true) {
				if($first[$x] -gt $second[$x]) {
					return $true
				}
				$x += 1
				if($x -gt $first.Length) {
					return $false
				}
			}
		}

		$moduledirectory = $MyInvocation.MyCommand.Module.ModuleBase

		$IdxRef = Get-DbaSqlBuildReferenceIndex
		$LastUpdated = Get-Date -Date $IdxRef.LastUpdated
		if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
			Write-Message -Message "Index is Stale, Last Update on: $(Get-Date -Date $LastUpdated -f s)" -Warning
		}

		function Resolve-DbaSqlBuild {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			[OutputType([System.Collections.Hashtable])]
			Param([string]$build)
			$LookFor = ($build.split('.')[0..2] | Foreach-Object { [convert]::ToInt32($_) }) -join '.'
			Write-Message -Message "Looking for $LookFor" -Level 5 -Silent $Silent
			$SqlVersion = $build.split('.')[0..1] -join '.'
			$IdxVersion = $IdxRef.Data | Where-Object Version -like "$SqlVersion.*"
			$Detected = @{}
			$Detected.MatchType = 'Approximate'
			Write-Message -Message "We have $($IdxVersion.Length) in store for this Release" -Level 5 -Silent $Silent
			If ($IdxVersion.Length -eq 0)
			{
				Write-Message -Message "No info in store for this Release" -Warning -Silent $Silent
				$Detected.Warning = "No info in store for this Release"
			}
			else
			{
				$LastVer = $IdxVersion[0]
			}
			foreach($el in $IdxVersion) {
				if($null -ne $el.Name) {
					$Detected.Name = $el.Name
				}
				if(Compare-DbaSqlBuildGreater -firstref $el.Version -secondref $LookFor) {
					$Detected.MatchType = 'Approximate'
					$Detected.Warning = "$LookFor not found, closest build we have is $($LastVer.Version)"
					break
				}
				$LastVer = $el
				if($null -ne $el.SP) {
					$Detected.SP = $el.SP
					$Detected.CU = $null
				}
				if($null -ne $el.CU) {
					$Detected.CU = $el.CU
				}
				if($null -ne $el.SupportedUntil) {
					$Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
				}
				$Detected.KB = $el.KBList
				if($el.Version -eq $LookFor) {
					$Detected.MatchType = 'Exact'
					break
				}
			}
			return $Detected
		}
	}
	PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			try {
				$null = $instance.Version.ToString()
			} catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Silent $Silent -Target $instance
			}
			$Detected = Resolve-DbaSqlBuild  $instance.Version.ToString()
			
			[PSCustomObject]@{
				SqlInstance = $instance.DomainInstanceName
				Build = $instance.Version.ToString()
				NameLevel = $Detected.Name
				SPLevel = $Detected.SP
				CULevel = $Detected.CU
				KBLevel = $Detected.KB
				SupportedUntil = $Detected.SupportedUntil
				MatchType = $Detected.MatchType
				Warning = $Detected.Warning
			}
		}
		
		foreach($buildstr in $Build) {
			$Detected = Resolve-DbaSqlBuild -Build $buildstr
			
			[PSCustomObject]@{
					SqlInstance = $null
					Build = $buildstr
					NameLevel = $Detected.Name
					SPLevel = $Detected.SP
					CULevel = $Detected.CU
					KBLevel = $Detected.KB
					SupportedUntil = $Detected.SupportedUntil
					MatchType = $Detected.MatchType
					Warning = $Detected.Warning
			} | Select-DefaultView -ExcludeProperty SqlInstance
		}
	}
}
