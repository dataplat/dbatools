function Get-DbaService {
<#
	.SYNOPSIS
		Uses WMI/CIM to scan for the existance of a specific windows services.
	
	.DESCRIPTION
		Uses WMI/CIM to scan for the existance of a specific windows services.
	
		Use Get-DbaSqlService if you are interested in scanning for sql server services exclusively.
	
	.PARAMETER ComputerName
		The computer to target. Uses localhost by default.
	
	.PARAMETER Name
		The name of the service to search for.
	
	.PARAMETER DisplayName
		The display-name of the service to search for.
	
	.PARAMETER Credential
		The credentials to use when connecting to the computer.
	
	.PARAMETER DoNotUse
		Connection Protocols that should not be used when retrieving the information.
	
	.PARAMETER Silent
	    Replaces user friendly yellow warnings with bloody red exceptions of doom!
	    Use this if you want the function to throw terminating errors you want to catch.
	
	.EXAMPLE
		Get-DbaService -Name LanmanServer
	
		Returns information on the LanmanServer service from localhost.
	
	.EXAMPLE
		Get-ADComputer -Filter * | Get-DbaService -Name Browser
	
		First retrieves all computer accounts from active directory, then scans all of those computers for the browser service.
		Note: THis may take seriously long time, you may also want to filter out computers that are offline before scanning for services.
	
	.EXAMPLE
		Get-DbaService -ComputerName "server1","server2","server3" -Name Lanman%
	
		Scans the servers server1, server2 and server3 for all services whose name starts with 'lanman'
#>
	[CmdletBinding()]
	Param (
		[string[]]
		$Name,
		
		[string[]]
		$DisplayName,
		
		[Parameter(ValueFromPipeline = $true)]
		[Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter[]]
		$ComputerName = $env:COMPUTERNAME,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[Sqlcollaborative.Dbatools.Connection.ManagementConnectionType[]]
		$DoNotUse,
		
		[switch]
		$Silent
	)
	
	begin {
		Write-Message -Level InternalComment -Message "Starting"
		Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
		
		if (-not (Test-Bound "Name") -and -not (Test-Bound "DisplayName")) {
			$Name = "%"
		}
	}
	process {
		:main foreach ($computer in $ComputerName) {
			Write-Message -Level VeryVerbose -Message "Processing queries to $($computer.ComputerName)" -Target $computer.ComputerName
			foreach ($serviceName in $Name) {
				Write-Message -Level Verbose -Message "Searching for services with name: $serviceName" -Target $computer.ComputerName
				try {
					if (Test-Bound "Credential") { Get-DbaCmObject -Query "SELECT * FROM Win32_Service WHERE Name LIKE '$serviceName'" -ComputerName $computer.ComputerName -Credential $Credential -Silent -DoNotUse $DoNotUse }
					else { Get-DbaCmObject -Query "SELECT * FROM Win32_Service WHERE Name LIKE '$serviceName'" -ComputerName $computer.ComputerName -Silent -DoNotUse $DoNotUse }
				}
				catch {
					if ($_.CategoryInfo.Category -eq "OpenError") {
						Stop-Function -Message "Failed to access computer $($computer.ComputerName)" -ErrorRecord $_ -Target $computer.ComputerName -Continue -ContinueLabel main
					}
					else {
						Stop-Function -Message "Failed to retrieve service" -ErrorRecord $_ -Target $computer.ComputerName -Continue
					}
				}
			}
			
			foreach ($serviceDisplayName in $DisplayName) {
				Write-Message -Level Verbose -Message "Searching for services with display name: $serviceDisplayName" -Target $computer.ComputerName
				try {
					if (Test-Bound "Credential") { Get-DbaCmObject -Query "SELECT * FROM Win32_Service WHERE DisplayName LIKE '$serviceDisplayName'" -ComputerName $computer.ComputerName -Credential $Credential -Silent -DoNotUse $DoNotUse }
					else { Get-DbaCmObject -Query "SELECT * FROM Win32_Service WHERE DisplayName LIKE '$serviceDisplayName'" -ComputerName $computer.ComputerName -Silent -DoNotUse $DoNotUse }
				}
				catch {
					if ($_.CategoryInfo.Category -eq "OpenError") {
						Stop-Function -Message "Failed to access computer $($computer.ComputerName)" -ErrorRecord $_ -Target $computer.ComputerName -Continue -ContinueLabel main
					}
					else {
						Stop-Function -Message "Failed to retrieve service" -ErrorRecord $_ -Target $computer.ComputerName -Continue
					}
				}
			}
		}
	}
	end {
		Write-Message -Level InternalComment -Message "Ending"
	}
}
