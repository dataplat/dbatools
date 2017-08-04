function Get-DbaMsdtc {
<#
.SYNOPSIS
Displays information about the Distributed Transactioon Coordinator (MSDTC) on a server

.DESCRIPTION
Returns a custom object with Computer name, state of the MSDTC Service, security settings of MSDTC and CID's

Requires: Windows administrator access on Servers

.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the computer as a different user.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: WSMan, CIM
Author: Klaas Vandenberghe ( powerdbaklaas )

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaMsdtc

.EXAMPLE
Get-DbaMsdtc -ComputerName srv0042

Get DTC status for the server srv0042

ComputerName                 : srv0042
DTCServiceName               : Distributed Transaction Coordinator
DTCServiceState              : Running
DTCServiceStatus             : OK
DTCServiceStartMode          : Manual
DTCServiceAccount            : NT AUTHORITY\NetworkService
DTCCID_MSDTC                 : b2aefacb-85d1-46b8-8047-7bb88e08d38a
DTCCID_MSDTCUIS              : 205bd32c-b022-4d0c-aa3e-2e5dc65c6d35
DTCCID_MSDTCTIPGW            : 3e743aa0-ead6-4569-ba7b-fe1aaea0a1eb
DTCCID_MSDTCXATM             : 667fc4b8-c2f5-4c3f-ad75-728b113f36c5
networkDTCAccess             : 0
networkDTCAccessAdmin        : 0
networkDTCAccessClients      : 0
networkDTCAccessInbound      : 0
networkDTCAccessOutBound     : 0
networkDTCAccessTip          : 0
networkDTCAccessTransactions : 0
XATransactions               : 0


.EXAMPLE
$Computers = (Get-Content D:\configfiles\SQL\MySQLInstances.txt | % {$_.split('\')[0]})
$Computers | Get-DbaMsdtc

Get DTC status for all the computers in a .txt file

.EXAMPLE
Get-DbaMsdtc -ComputerName $Computers | where { $_.dtcservicestate -ne 'running' }

Get DTC status for all the computers where the MSDTC Service is not running


.EXAMPLE
Get-DbaMsdtc -ComputerName srv0042 | Out-Gridview

Get DTC status for the computer srv0042 and show in a grid view

#>
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias('cn', 'host', 'Server')]
		[DbaInstanceParameter[]]$ComputerName = $env:ComputerName,
		[PSCredential]$Credential,
		[switch]$Silent
	)
	
	begin {
		$DTCSecurity = {
			Get-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security |
			Select-Object PSPath, PSComputerName, AccountName, networkDTCAccess,
						  networkDTCAccessAdmin, networkDTCAccessClients, networkDTCAccessInbound,
						  networkDTCAccessOutBound, networkDTCAccessTip, networkDTCAccessTransactions, XATransactions
		}
		$DTCCIDs = {
			New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
			Get-ItemProperty -Path HKCR:\CID\*\Description |
			Select-Object @{ l = 'Data'; e = { $_.'(default)' } }, @{ l = 'CID'; e = { $_.PSParentPath.split('\')[-1] } }
			Remove-PSDrive -Name HKCR | Out-Null
		}
	}
	process {
		foreach ($Computer in $ComputerName.ComputerName) {
			$reg = $CIDs = $null
			$CIDHash = @{ }
			if ($credential) {
				Test-PSRemoting -ComputerName $Computer -Credential $Credential
			}
			else {
				Test-PSRemoting -ComputerName $Computer
			}
			if ($remoting) {
				$dtcservice = $null
				
				Write-Message -Level Verbose -Message "Getting DTC on $computer via WSMan"
				$scriptblock = { Get-Ciminstance -Query "Select * FROM Win32_Service WHERE Name = 'MSDTC'" }
				
				$dtcservice = Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $scriptblock
				
				$dtcservice =
				if ($null -eq $dtcservice) {
					Write-Message -Level Verbose -Message "Can't connect to CIM on $Computer via WSMan"
				}
				
				Write-Message -Level Verbose -Message "Getting MSDTC Security Registry Values on $Computer"
				$reg = Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $DTCSecurity
				
				if ($null -eq $reg) {
					Write-Message -Level Verbose -Message "Can't connect to MSDTC Security registry on $Computer"
				}
				
				Write-Message -Level Verbose -Message "Getting MSDTC CID Registry Values on $Computer"
				$CIDs = Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $DTCCIDs
				if ($null -ne $CIDs) {
					foreach ($key in $CIDs) { $CIDHash.Add($key.Data, $key.CID) }
				}
				else {
					Write-Message -Level Verbose -Message "Can't connect to MSDTC CID registry on $Computer"
				}
			}
			else {
				
				Write-Message -Level Verbose -Message "PSRemoting is not enabled on $Computer"
				try {
					Write-Message -Level Verbose -Message "Failed To get DTC via WinRM. Getting DTC on $computer via DCom"
					$SessionParams = @{ }
					$SessionParams.ComputerName = $Computer
					$SessionParams.SessionOption = (New-CimSessionOption -Protocol Dcom)
					$Session = New-CimSession @SessionParams
					$dtcservice = Get-Ciminstance -CimSession $Session -Query "Select * FROM Win32_Service WHERE Name = 'MSDTC'"
				}
				catch {
					Write-Message -Level Verbose -Message "Can't connect to CIM on $Computer via DCom"
					continue
				}
			}
			if ($dtcservice) {
				[PSCustomObject]@{
					ComputerName    = $dtcservice.PSComputerName
					DTCServiceName  = $dtcservice.DisplayName
					DTCServiceState = $dtcservice.State
					DTCServiceStatus = $dtcservice.Status
					DTCServiceStartMode = $dtcservice.StartMode
					DTCServiceAccount = $dtcservice.StartName
					DTCCID_MSDTC    = $CIDHash['MSDTC']
					DTCCID_MSDTCUIS = $CIDHash['MSDTCUIS']
					DTCCID_MSDTCTIPGW = $CIDHash['MSDTCTIPGW']
					DTCCID_MSDTCXATM = $CIDHash['MSDTCXATM']
					networkDTCAccess = $reg.networkDTCAccess
					networkDTCAccessAdmin = $reg.networkDTCAccessAdmin
					networkDTCAccessClients = $reg.networkDTCAccessClients
					networkDTCAccessInbound = $reg.networkDTCAccessInbound
					networkDTCAccessOutBound = $reg.networkDTCAccessOutBound
					networkDTCAccessTip = $reg.networkDTCAccessTip
					networkDTCAccessTransactions = $reg.networkDTCAccessTransactions
					XATransactions  = $reg.XATransactions
				}
			}
		}
	}
}
