#requires -version 3.0
 
Function Test-PSRemoting {
<#
Jeff Hicks
https://www.petri.com/test-network-connectivity-powershell-test-connection-cmdlet
#>
	[cmdletbinding()]
	param(
	[Parameter(Position=0,Mandatory,ValueFromPipeline)]
	[DbaInstance]$ComputerName,
	$Credential = [System.Management.Automation.PSCredential]::Empty,
	[switch]$Silent
	)

	process {
		Write-Message -Level VeryVerbose -Message "Testing $($ComputerName.Computername)"
		try {
			$r = Test-WSMan -ComputerName $ComputerName.ComputerName -Credential $Credential -Authentication Default -ErrorAction Stop
			$true
		}
		catch {
			Write-Message -Level Verbose -Message "Testing $($ComputerName.Computername)" -Target $ComputerName -ErrorRecord $_
			$false
		}

	} #Process

} #close function
