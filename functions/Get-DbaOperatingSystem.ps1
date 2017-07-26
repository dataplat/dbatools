function Get-DbaOperatingSystem {
	<#
		.SYNOPSIS
			Gets operating system information from the server.

		.DESCRIPTION
			Gets operating system information from the server and returns as an object.

		.PARAMETER ComputerName
			Target computer(s). If no computer name is specified, the local computer is targeted

		.PARAMETER Credential
			Alternate credential object to use for accessing the target computer(s).

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: ServerInfo, OperatingSystem
			Original Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

			Website: https: //dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https: //opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaOperatingSystem

		.EXAMPLE
			Get-DbaOperatingSystem

			Returns information about the local computer's operating system

		.EXAMPLE
			Get-DbaOperatingSystem -ComputerName sql2016

			Returns information about the sql2016's operating system
	#>
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("cn","host","Server")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[switch]$Silent
	)
	process {
		foreach ($computer in $ComputerName) {
			Write-Message -Level Verbose -Message "Attempting to connect to $computer"
			$server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

			$computerResolved = $server.ComputerName

			if (!$computerResolved) {
				Write-Message -Level Warning -Message "Unable to resolve hostname of $computer. Skipping."
				continue
			}

			if (Test-Bound "Credential") {
				$os = Get-DbaCmObject -ClassName Win32_OperatingSystem -ComputerName $computerResolved -Credential $Credential
				$tz = Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $computerResolved -Credential $Credential
				$powerPlan = Get-DbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" -ComputerName $computerResolved -Credential $Credential | Select-Object ElementName, InstanceId, IsActive
			}
			else {
				$os = Get-DbaCmObject -ClassName Win32_OperatingSystem -ComputerName $computerResolved
				$tz = Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $computerResolved
				$powerPlan = Get-DbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" -ComputerName $computerResolved | Select-Object ElementName, InstanceId, IsActive
			}

			$activePowerPlan = ($powerPlan | Where-Object IsActive).ElementName -join ','
			$language = Get-Language $os.OSLanguage
			
			[PSCustomObject]@{
				ComputerName   = $computer.ComputerName
				Manufacturer   = $os.Manufacturer
				Organization   = $os.Organization
				Architecture   = $os.OSArchitecture
				Version	       = $os.Version
				Build		   = $os.BuildNumber
				InstallDate    = [DbaDateTime]$os.InstallDate
				LastBootTime   = [DbaDateTime]$os.LastBootUpTime
				LocalDateTime  = [DbaDateTime]$os.LocalDateTime
				TimeZone	   = $tz.Caption
				TimeZoneStandard = $tz.StandardName
				TimeZoneDaylight = $tz.DaylightName
				BootDevice	   = $os.BootDevice
				TotalVisibleMemory = [DbaSize]($os.TotalVisibleMemorySize * 1024)
				FreePhysicalMemory = [DbaSize]($os.FreePhysicalMemory * 1024)
				TotalVirtualMemory = [DbaSize]($os.TotalVirtualMemorySize * 1024)
				FreeVirtualMemory = [DbaSize]($os.FreeVirtualMemory * 1024)
				ActivePowerPlan = $activePowerPlan
				Language	   = $language.Name
				LanguageAlias  = $language.Alias
				LanguageId	   = $language.LanguageID
				CodeSet	       = $os.CodeSet
				CountryCode    = $os.CountryCode
				Locale		   = $os.Locale
			} | Select-DefaultView -ExcludeProperty Codeset, CountryCode, Locale, LanguageID, LanguageAlias
			
			#$defaults = 'ComputerName','InstanceName','SqlInstance','Manufacturer','Architecture','Build','Version','InstallDate','LastBootTime','LocalDateTime'
		}
	}
}