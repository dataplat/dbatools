Function Get-DbaSqlBuildReference
{
<#
.SYNOPSIS
Returns SQL Server Build infos on a SQL instance

.DESCRIPTION
Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
It also includes End Of Support dates as specified on Microsoft Lifecycle Policy

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER Build
Instead of connecting to a real instance, pass a string identifying the build to get the info back.

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
Get-DbaSqlBuildReference -SqlInstance sqlserver2014a

Returns SqlInstance, SPLevel, CULevel, KBLevel, SupportedUntil for server sqlserver2014a

.EXAMPLE
$cred = Get-Credential sqladmin
Get-DbaSqlBuildReference -SqlInstance sqlserver2014a -SqlCredential $cred

Does the same as above but logs in as SQL user "sqladmin"

.EXAMPLE
Get-DbaSqlBuildReference -Build "12.00.4502"

Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	Param (
		[Parameter(
			ParameterSetName='Server',
			Mandatory = $true,
			ValueFromPipeline = $true
		)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[parameter(ParameterSetName = "Server")]
		[PSCredential]
		[System.Management.Automation.CredentialAttribute()]$Credential,
		[Parameter(
			ParameterSetName='BuildString'
		)]
		[string[]]$Build
	)

	BEGIN {
		function Find-DbaSqlBuildReferenceIndex {
			[CmdletBinding()]
			Param()
			$idxfile = "$moduledirectory\bin\dbatools-buildref-index.json"
			if (!(Test-Path $idxfile)) {
				Write-Warning "Unable to read local file"
			} else {
				return (Get-Content $idxfile)
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
			Write-Warning "Index is Stale, Last Update on: $(Get-Date -Date $LastUpdated -f s)"
		}

		function Resolve-DbaSqlBuild {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			[OutputType([System.Collections.Hashtable])]
			Param([string]$build)
			$LookFor = ($build.split('.')[0..2] | Foreach-Object { [convert]::ToInt32($_) }) -join '.'
			Write-Verbose "Looking for $LookFor"
			$SqlVersion = $build.split('.')[0..1] -join '.'
			$IdxVersion = $IdxRef.Data | Where-Object Version -like "$SqlVersion.*"
			$Detected = @{}
			$MatchType = 'Approximate'
			Write-Verbose "We have $($IdxVersion.Length) in store for this Release"
			If($IdxVersion.Length -eq 0) {
				Write-Warning "No info in store for this Release"
				$Detected.Warning = "No info in store for this Release"
			}
			$LastVer = $IdxVersion[0]
			foreach($el in $IdxVersion) {
				if($null -ne $el.Name) {
					$Detected.Name = $el.Name
				}
				if(Compare-DbaSqlBuildGreater -firstref $el.Version -secondref $LookFor) {
					$MatchType = 'Approximate'
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
					$MatchType = 'Exact'
					break
				}
			}
			return $Detected
		}
	}
	PROCESS {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Connecting to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $Credential
			} catch {
				Write-Warning "Can't connect to $instance"
				Continue
			}
			$LookFor = $server.Version.toString()
			$Detected = Resolve-DbaSqlBuild $LookFor
			$object = [PSCustomObject]@{
					SqlInstance   = $server.Name
					InstanceName  = $server.ServiceName
					ComputerName  = $server.NetName
					NameLevel = $Detected.Name
					SPLevel = $Detected.SP
					CULevel = $Detected.CU
					KBLevel = $Detected.KB
					SupportedUntil = $Detected.SupportedUntil
					MatchType = $MatchType
					Warning = $Detected.Warning
					Version = $LookFor
					Instance = $server
			}
			Select-DefaultView -InputObject $object -Property SqlInstance, Version, NameLevel, SPLevel, CULevel, KBLevel, SupportedUntil, MatchType, Warning
		}
		foreach($buildstr in $Build) {
			$Detected = Resolve-DbaSqlBuild $buildstr
			$object = [PSCustomObject]@{
					NameLevel = $Detected.Name
					SPLevel = $Detected.SP
					CULevel = $Detected.CU
					KBLevel = $Detected.KB
					SupportedUntil = $Detected.SupportedUntil
					MatchType = $MatchType
					Warning = $Detected.Warning
					Version = $buildstr
			}
			Select-DefaultView -InputObject $object -Property Version, NameLevel, SPLevel, CULevel, KBLevel, SupportedUntil, MatchType, Warning
		}
	}
}
