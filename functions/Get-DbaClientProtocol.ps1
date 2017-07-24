function Get-DbaClientProtocol {
	<#
		.SYNOPSIS
			Gets the SQL Server related client protocols on a computer.

		.DESCRIPTION
			Gets the SQL Server related client protocols on one or more computers.

			Requires Local Admin rights on destination computer(s).
			The client protocols can be enabled and disabled when retrieved via WSMan.

		.PARAMETER ComputerName
			The SQL Server (or server in general) that you're connecting to. This command handles named instances.

		.PARAMETER Credential
			Credential object used to connect to the computer as a different user.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Protocol
			Author: Klaas Vandenberghe ( @PowerDBAKlaas )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaClientProtocol

		.EXAMPLE
			Get-DbaClientProtocol -ComputerName sqlserver2014a

			Gets the SQL Server related client protocols on computer sqlserver2014a.

		.EXAMPLE
			'sql1','sql2','sql3' | Get-DbaClientProtocol

			Gets the SQL Server related client protocols on computers sql1, sql2 and sql3.

		.EXAMPLE
			Get-DbaClientProtocol -ComputerName sql1,sql2 | Out-Gridview

			Gets the SQL Server related client protocols on computers sql1 and sql2, and shows them in a grid view.

		.EXAMPLE
			(Get-DbaClientProtocol -ComputerName sql1 | Where { $_.DisplayName = 'via' }).Disable()

			Disables the VIA ClientNetworkProtocol on computer sql1.
			If succesfull, returncode 0 is shown.
#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("cn", "host", "Server")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential] $Credential,
		[switch]$Silent
	)

	begin {
		$ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
	}
	process {
		foreach ( $computer in $ComputerName ) {
			$server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
			if ( $server.ComputerName ) {
				$computer = $server.ComputerName
				
				Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer via CIM (WSMan)"
				$namespace = Get-CimInstance -ComputerName $computer -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
					Where-Object {(Get-CimInstance -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
					Sort-Object Name -Descending | Select-Object -First 1

				if ( $namespace.Name ) {
					Write-Message -Level Verbose -Message "Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $computer via CIM (WSMan)"
					try {
						$prot = Get-CimInstance -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue

						$prot | Add-Member -Force -MemberType ScriptProperty -Name IsEnabled -Value { switch ( $this.ProtocolOrder ) { 0 { $false } default { $true } } }
						$prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
						$prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }
						
						foreach ( $protocol in $prot ) {
							Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'ProtocolDisplayName as DisplayName', 'ProtocolDll as DLL', 'ProtocolOrder as Order', 'IsEnabled'
						}
					}
					catch {
						Write-Message -Level Warning -Message "No Sql ClientNetworkProtocol found on $computer via CIM (WSMan)"
					}
				} #if namespace WSMan
				else {
					Write-Message -Level Verbose -Message "Getting computer information from $computer via CIMsession (DCOM)"
					
					$sessionOption = New-CimSessionOption -Protocol DCOM
					$CIMsession = New-CimSession -ComputerName $computer -SessionOption $sessionOption -ErrorAction SilentlyContinue -Credential $Credential
					
					if ( $CIMSession ) {
						Write-Message -Level Verbose -Message "Get ComputerManagement Namespace in CIMsession on $computer with protocol DCom."
						
						$namespace = Get-CimInstance -CimSession $CIMsession -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
							Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
							Sort-Object Name -Descending | Select-Object -First 1
					} #if CIMsession DCom
					else {
						Write-Message -Level Warning -Message "Can't create CIMsession via DCom on $computer"
						continue
					} #else no CIMsession DCom
					if ( $namespace.Name ) {
						Write-Message -Level Verbose -Message "Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $computer via CIM (DCOM)"
						try {
							$prot = Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue
							
							$prot | Add-Member -Force -MemberType ScriptProperty -Name IsEnabled -Value { switch ( $this.ProtocolOrder ) { 0 { $false } default { $true } } }
							$prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
							$prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }
							
							foreach ( $protocol in $prot ) {
								Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'ProtocolDisplayName as DisplayName', 'ProtocolDll as DLL', 'ProtocolOrder as Order', 'IsEnabled'
							}
						}
						catch {
							Write-Message -Level Warning -Message "No Sql ClientNetworkProtocol found on $computer via CIM (DCOM)"
						}
						if ( $CIMsession ) { Remove-CimSession $CIMsession }
					} #if namespace DCom
					else {
						Write-Message -Level Warning -Message "No ComputerManagement Namespace on $computer. Please note that this function is available from SQL 2005 up."
					} #else no namespace DCom
				} #else no namespace WSMan
			} #if computername
			else {
				Write-Message -Level Warning -Message "Failed to connect to $computer"
			}
		} #foreach computer
	}
}
