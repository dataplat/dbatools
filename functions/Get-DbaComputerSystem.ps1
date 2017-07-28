function Get-DbaComputerSystem {
	<#
		.SYNOPSIS
			Gets computer system information from the server.

		.DESCRIPTION
			Gets computer system information from the server and returns as an object.

		.PARAMETER ComputerName
			Target computer(s). If no computer name is specified, the local computer is targeted

		.PARAMETER Credential
			Alternate credential object to use for accessing the target computer(s).

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: ServerInfo
			Original Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

			Website: https: //dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https: //opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaComputerSystem

		.EXAMPLE
			Get-DbaComputerSystem

			Returns information about the local computer's operating system

		.EXAMPLE
			Get-DbaComputerSystem -ComputerName sql2016

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
				$computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved -Credential $Credential
			}
			else {
				$computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved
			}
			
			$adminPasswordStatus = 
				switch ($computerSystem.AdminPasswordStatus) {
					0 {"Disabled"}
					1 {"Enabled"}
					2 {"Not Implemented"}
					3 {"Unknown"}
					default {"Unknown"}
				}
			$domainRole = 
				switch ($computerSystem.DomainRole) {
					0 {"Standalone Workstation"}
					1 {"Member Workstation"}
					2 {"Standalone Server"}
					3 {"Member Server"}
					4 {"Backup Domain Controller"}
					5 {"Primary Domain Controller"}
				}
				$isHyperThreading = $false
				if ($computerSystem.NumberOfLogicalProcessors -gt $computerSystem.NumberofProcessors) {
					$isHyperThreading = $true
				}

			[PSCustomObject]@{
				ComputerName            = $computer.ComputerName
				Domain                  = $computerSystem.Domain
				DomainRole              = $domainRole
				Manufacturer            = $computerSystem.Manufacturer
				Model                   = $computerSystem.Model
				SystemFamily            = $computerSystem.SystemFamily
				SystemSkuNumber         = $computerSystem.SystemSKUNumber
				SystemType              = $computerSystem.SystemType
				NumberLogicalProcessors = $computerSystem.NumberOfLogicalProcessors
				NumberProcessors        = $computerSystem.NumberOfProcessors
				IsHyperThreading        = $isHyperThreading
				TotalPhysicalMemory     = [DbaSize]$computerSystem.TotalPhysicalMemory
				IsDaylightSavingsTime   = $computerSystem.EnableDaylightSavingsTime
				DaylightInEffect        = $computerSystem.DaylightInEffect
				DnsHostName             = $computerSystem.DNSHostName
				IsSystemManagedPageFile   = $computerSystem.AutomaticManagedPagefile
				AdminPasswordStatus     = $adminPasswordStatus
			} | Select-DefaultView -ExcludeProperty SystemSkuNumber, IsDaylightSavingsTime,DaylightInEffect,DnsHostName,AdminPasswordStatus
		}
	}
}