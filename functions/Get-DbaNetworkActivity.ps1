function Get-DbaNetworkActivity {
  <#
      .SYNOPSIS
      Gets the Current traffic on every Network Interface on a computer.

      .DESCRIPTION
      Gets the Current traffic on every Network Interface on a computer.
      See https://msdn.microsoft.com/en-us/library/aa394293(v=vs.85).aspx

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .PARAMETER Silent
      Use this switch to disable any kind of verbose messages
	
      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Network
	
      Website: https://dbatools.io
      Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
      License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
      .LINK
      https://dbatools.io/Get-DbaNetworkActivity

      .EXAMPLE
      Get-DbaNetworkActivity -ComputerName sqlserver2014a
      
      Gets the Current traffic on every Network Interface on computer sqlserver2014a.

      .EXAMPLE   
      'sql1','sql2','sql3' | Get-DbaNetworkActivity
      
      Gets the Current traffic on every Network Interface on computers sql1, sql2 and sql3.

      .EXAMPLE
      Get-DbaNetworkActivity -ComputerName sql1,sql2 | Out-Gridview

      Gets the Current traffic on every Network Interface on computers sql1 and sql2, and shows them in a grid view.

  #>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("cn", "host", "Server")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[switch]$Silent
	)
	
	begin {
		$sessionoption = New-CimSessionOption -Protocol DCom
	}
	process {
		foreach ($computer in $ComputerName.ComputerName) {
			$props = @{ "ComputerName" = $computer }
			$Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
			if ($Server.ComputerName) {
				$Computer = $server.ComputerName
				Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan"
				$CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
				if (-not $CIMSession) {
					Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
					$CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
				}
				if ($CIMSession) {
					Write-Message -Level Verbose -Message "Getting properties for Network Interfaces on $computer"
					$nics = Get-CimInstance -CimSession $CIMSession -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface
					$nics | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { $computer }
					$nics | Add-Member -Force -MemberType ScriptProperty -Name Bandwith -Value {
						switch ($this.CurrentBandWidth) {
							10000000000 { '10Gb' } 1000000000 { '1Gb' } 100000000 { '100Mb' } 10000000 { '10Mb' } 1000000 { '1Mb' } 100000 { '100Kb' }
							default { 'Low' }
						}
					}
					foreach ($nic in $nics) { Select-DefaultView -InputObject $nic -Property 'ComputerName', 'Name as NIC', 'BytesReceivedPersec', 'BytesSentPersec', 'BytesTotalPersec', 'Bandwith' }
				}
				else {
					Write-Message -Level Warning -Message "Can't create CIMSession on $computer"
				}
			}
			else {
				Write-Message -Level Warning -Message "Can't connect to $computer"
			}
		}
	}
}