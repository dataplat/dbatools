Function Get-DbaSqlBuildReference {
<#
	.SYNOPSIS
		Returns SQL Server Build infos on a SQL instance
	
	.DESCRIPTION
		Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
		It also includes End Of Support dates as specified on Microsoft Lifecycle Policy
	
	.PARAMETER Build
		Instead of connecting to a real instance, pass a string identifying the build to get the info back.
	
	.PARAMETER SqlInstance
		Target any number of instances, in order to return their build state.
	
	.PARAMETER SqlCredential
		When connecting to an instance, use the credentials specified.
	
	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages
	
	.EXAMPLE
		Get-DbaSqlBuildReference -Build "12.00.4502"
		
		Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)
	
	.EXAMPLE
		Get-DbaSqlBuildReference -Build "12.0.4502","10.50.4260"
		
		Returns information builds identified by these versions strings
	
	.EXAMPLE
		Get-DbaRegisteredServerName -SqlInstance sqlserver2014a | Get-DbaSqlBuildReference
		
		Integrate with other commandlets to have builds checked for all your registered servers on sqlserver2014a
	
	.NOTES
		Author: niphlod
		Editor: Fred
		Tags: SqlBuild
		
		dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
		Copyright (C) 2016 Chrissy LeMaire
		This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
		This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
		You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
	.LINK
		https://dbatools.io/Get-DbaSqlBuildReference
#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	Param (
		[version[]]
		$Build,
		
		[parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]
		$SqlInstance,
		
		[Alias("Credential")]
		[PsCredential]
		$SqlCredential,
		
		[switch]
		$Silent
	)
	
	begin {
		#region Helper functions
		function Get-DbaSqlBuildReferenceIndex {
			[CmdletBinding()]
			Param (
				[string]
				$Moduledirectory,
				
				[bool]
				$Silent
			)
			
			$orig_idxfile = "$Moduledirectory\bin\dbatools-buildref-index.json"
			$DbatoolsData = Get-DbaConfigValue -Name 'Path.DbatoolsData'
			$writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"
			
			if (-not (Test-Path $orig_idxfile)) {
				Write-Message -Level Warning -Silent $Silent -Message "Unable to read local SQL build reference file. Check your module integrity!"
			}
			
			if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
				throw "Build reference file not found, check module health!"
			}
			
			# If no writable copy exists, create one and return the module original
			if (-not (Test-Path $writable_idxfile)) {
				Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
				$result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
			}
			
			# Else, if both exist, update the writeable if necessary and return the current version
			elseif (Test-Path $orig_idxfile) {
				$module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
				$data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
				
				$module_time = Get-Date $module_content.LastUpdated
				$data_time = Get-Date $data_content.LastUpdated
				
				if ($module_time -gt $data_time) {
					Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
					$result = $module_content
				}
				
				else {
					$result = $data_content
				}
			}
			
			# Else if the module version of the file no longer exists, but the writable version exists, return the writable version
			else {
				$result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
			}
			
			$LastUpdated = Get-Date -Date $result.LastUpdated
			if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
				Write-Message -Level Warni -Silent $Silent -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s)"
			}
			
			$result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
		}
		
		function Resolve-DbaSqlBuild {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			[OutputType([System.Collections.Hashtable])]
			Param (
				[version]
				$Build,
				
				$Data,
				
				[bool]
				$Silent
			)
			
			Write-Message -Level Verbose -Silent $Silent -Message "Looking for $Build"
			
			$IdxVersion = $Data | Where-Object Version -like "$($Build.Major).$($Build.Minor).*"
			$Detected = @{ }
			$Detected.MatchType = 'Approximate'
			Write-Message -Level Verbose -Silent $Silent -Message "We have $($IdxVersion.Length) builds in store for this Release"
			If ($IdxVersion.Length -eq 0) {
				Write-Message -Level Warning -Silent $Silent -Message "No info in store for this Release"
				$Detected.Warning = "No info in store for this Release"
			}
			else {
				$LastVer = $IdxVersion[0]
			}
			foreach ($el in $IdxVersion) {
				if ($null -ne $el.Name) {
					$Detected.Name = $el.Name
				}
				if ($el.VersionObject -gt $Build) {
					$Detected.MatchType = 'Approximate'
					$Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
					break
				}
				$LastVer = $el
				if ($null -ne $el.SP) {
					$Detected.SP = $el.SP
					$Detected.CU = $null
				}
				if ($null -ne $el.CU) {
					$Detected.CU = $el.CU
				}
				if ($null -ne $el.SupportedUntil) {
					$Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
				}
				$Detected.KB = $el.KBList
				if ($el.Version -eq $Build) {
					$Detected.MatchType = 'Exact'
					break
				}
			}
			return $Detected
		}
		#endregion Helper functions
		
		$moduledirectory = $MyInvocation.MyCommand.Module.ModuleBase
		
		try {
			$IdxRef = Get-DbaSqlBuildReferenceIndex -Moduledirectory $moduledirectory -Silent $Silent
		}
		catch {
			Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
			return
		}
	}
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			#region Ensure the connection is established
			try {
				Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
			}
			
			try {
				$null = $server.Version.ToString()
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Silent $Silent -Target $instance
			}
			#endregion Ensure the connection is established
			
			$Detected = Resolve-DbaSqlBuild -Build $server.Version -Data $IdxRef -Silent $Silent
			
			[PSCustomObject]@{
				SqlInstance    = $server.DomainInstanceName
				Build		   = $server.Version
				NameLevel	   = $Detected.Name
				SPLevel	       = $Detected.SP
				CULevel	       = $Detected.CU
				KBLevel	       = $Detected.KB
				SupportedUntil = $Detected.SupportedUntil
				MatchType	   = $Detected.MatchType
				Warning	       = $Detected.Warning
			}
		}
		
		foreach ($buildstr in $Build) {
			$Detected = Resolve-DbaSqlBuild -Build $buildstr -Data $IdxRef -Silent $Silent
			
			[PSCustomObject]@{
				SqlInstance    = $null
				Build		   = $buildstr
				NameLevel	   = $Detected.Name
				SPLevel	       = $Detected.SP
				CULevel	       = $Detected.CU
				KBLevel	       = $Detected.KB
				SupportedUntil = $Detected.SupportedUntil
				MatchType	   = $Detected.MatchType
				Warning	       = $Detected.Warning
			} | Select-DefaultView -ExcludeProperty SqlInstance
		}
	}
}
