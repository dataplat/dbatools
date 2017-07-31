function Import-OldSmo {
	<#
	.SYNOPSIS
	Attempts to import older versions of SMO for things like Integrated Services

	.DESCRIPTION
	SMO 14, which is not yet RTM, does not appear to support Integrated Services Commands. 
	This helps.

	.EXAMPLE 
	Import-OldSmo

	#>

	$smoversions = "13.0.0.0", "12.0.0.0", "11.0.0.0", "10.0.0.0", "9.0.242.0", "9.0.0.0"

	foreach ($smoversion in $smoversions) {
		try {
			Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
			$smoadded = $true
		}
		catch {
			$smoadded = $false
		}
		
		if ($smoadded -eq $true) { break }
	}
	
	if ($smoadded -eq $false) {
		throw "Sorry! The current SMO files we pre-package do not yet support some things. Run this on a computer with SSMS 2016 or below."
	}
	
	$assemblies = "Management.Common", "Dmf", "Instapi", "SqlWmiManagement", "ConnectionInfo", "SmoExtended", "SqlTDiagM", "Management.Utility",
	"SString", "Management.RegisteredServers", "Management.Sdk.Sfc", "SqlEnum", "RegSvrEnum", "WmiEnum", "ServiceBrokerEnum", "Management.XEvent",
	"ConnectionInfoExtended", "Management.Collector", "Management.CollectorEnum", "Management.Dac", "Management.DacEnum", "Management.IntegrationServices"
	
	foreach ($assembly in $assemblies) {
		try {
			Add-Type -AssemblyName "Microsoft.SqlServer.$assembly, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
		}
		catch {
			# Don't care
		}
	}
}