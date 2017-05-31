function Test-RunAsAdmin {
<#     
	.SYNOPSIS
	Ensures the command is run as administrator.

	.DESCRIPTION
	Ensures the command is run as administrator. This command will send a warning and a "break" to any script that is running without elevated privileges.
	
	.EXAMPLE
	Test-RunAsAdmin
	
	Tests to ensure the user is running as admin.
	  
#>	
	[CmdletBinding()]
	param
	(
		[string]$ComputerName
	)
	
	if ($ComputerName -and $ComputerName -eq $env:COMPUTERNAME) {
		if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
			Stop-Function -Message "Administrative rights required. Run this command again with elevated privileges."
			break
		}
	}
	else {
		if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
			Stop-Function -Message "Administrative rights required. Run this command again with elevated privileges."
			break
		}
	}
}