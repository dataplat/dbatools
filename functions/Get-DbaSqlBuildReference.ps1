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

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

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
Get-DbaSqlBuildReference -SqlServer sqlserver2014a

Returns SqlInstance, SPLevel, CULevel, KBLevel for server sqlserver2014a

.EXAMPLE
$cred = Get-Credential sqladmin
Get-DbaSqlBuildReference -SqlServer sqlserver2014a -SqlCredential $cred
Does the same as above but logs in as SQL user "sqladmin"

.EXAMPLE
Get-DbaSqlBuildReference -SqlServer sqlserver2014a -SqlCredential $cred
Does the same as above but logs in as SQL user "sqladmin"
	
#>

	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]
		[System.Management.Automation.CredentialAttribute()]$SqlCredential
	)

	BEGIN {
		function Find-DbaSqlBuildReferenceIndex() {
			$idxfile = "$moduledirectory\bin\dbatools-buildref-index.json"
			if (!(Test-Path $idxfile)) {
				Write-Warning "Unable to read local file"
			} else {
				return (Get-Content $idxfile)
			}
		}

		function Get-DbaSqlBuildReferenceIndex() {
			return Find-DbaSqlBuildReferenceIndex | ConvertFrom-Json
		}

		$moduledirectory = (Get-Module -Name dbatools).ModuleBase

		$IdxRef = Get-DbaSqlBuildReferenceIndex
	}
	PROCESS {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Connecting to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
			} catch {
				Write-Warning "Can't connect to $instance"
				Continue
			}
			$LookFor = "$($server.Version.Major).$($server.Version.Minor).$($server.Version.Build)"
			Write-Verbose "Looking for $LookFor"
			$IdxVersion = $IdxRef | Where-Object Version -like "$($server.Version.Major).$($server.Version.Minor).*"
			$Detected = @{}
			$MatchType = 'Approximate'
			Write-Verbose "We have $($IdxVersion.Length) in store"
			If($IdxVersion.Length -eq 0) {
				Write-Warning "No info in store for this Version"
				$Detected.Warning = "No info in store for this Version"
			}
			foreach($el in $IdxVersion) {
				if($null -ne $el.Name) {
					$Detected.Name = $el.Name
				}
				if($null -ne $el.SP) {
					$Detected.SP = $el.SP
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
			$object = [PSCustomObject]@{
					ComputerName  = $server.NetName
					InstanceName  = $server.ServiceName
					SqlInstance   = $server.Name
					NameLevel = $Detected.Name
					SPLevel = $Detected.SP
					CULevel = $Detected.CU
					KBLevel = $Detected.KB
					SupportedUntil = $Detected.SupportedUntil
					MatchType = $MatchType
					Warning = $Detected.Warning
					Instance = $server
			}
			Select-DefaultView -InputObject $object -Property SqlInstance, NameLevel, SPLevel, CULevel, KBLevel, SupportedUntil, MatchType, Warning
		}
	}

}
