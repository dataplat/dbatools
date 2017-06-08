function Get-DbaServerOperatingSystem {
	<#
		.SYNOPSIS
			Gets operating system information from the server.

		.DESCRIPTION
			Gets operating system information from the server and returns an object.

		.PARAMETER ComputerName
			The SQL Server (or server in general) that you're connecting to.

		.PARAMETER Credential
			Credential object used to connect to the server as a different user

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages.

		.NOTES
			Tags: ServerInfo
			Original Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

			Website: https: //dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https: //opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaServerOperatingSystem

		.EXAMPLE
			Get-DbaServerOperatingSystem
			Example of how to use this cmdlet

		.EXAMPLE
			Get-DbaServerOperatingSystem
			Another example of how to use this cmdlet
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position= 0, Mandatory= $true, ValueFromPipeline= $true)]
		[string[]]$ComputerName,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential,
		[switch]$Silent
	)

	process {
		foreach ($computer in $ComputerName) {
			Write-Message -Level Verbose -Message "Attempting to connect to $computer"
			$server = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
			
			$computerResolved = $server.ComputerName
			
			if (!$computerResolved) {
				Write-Message -Level Warning -Message "Unable to resolve hostname of $computer. Skipping."
				continue
			}
			
			if (Was-Bound "Credential") {
				Get-DbaCmObject -ClassName win32_OperatingSystem -ComputerName $computerResolved -Credential $Credential
			}
			else {
				Get-DbaCmObject -ClassName win32_OperatingSystem -ComputerName $computerResolved
			}

			[pscustomobject]@{
				Server = $computerResolved
			}
			
		} #end foreach instance
	} #end process
} #end function