Function Get-DbaMsdtc
{
<#
.SYNOPSIS
Displays information about the Distributed Transactioon Coordinator (MSDTC) on a server

.DESCRIPTION
Returns a custom object with Computer name, state of the MSDTC Service, security settings of MSDTC and CID's

Requires: Windows administrator access on Servers

.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to.

.NOTES
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
Get-DbaMsdtc -Computername $Computers | where { $_.dtcservicestate -ne 'running' }

Get DTC status for all the computers where the MSDTC Service is not running


.EXAMPLE
Get-DbaMsdtc -ComputerName srv0042 | Out-Gridview


Get DTC status for the computer srv0042 and show in a grid view

#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("cn", "host", "Server")]
		[string[]]$Computername
	)
	
	BEGIN
	{
		$query = "Select * FROM Win32_Service WHERE Name = 'MSDTC'"
		$DTCSecurity = {
			Get-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security |
			Select-Object PSPath, PSComputerName, AccountName, networkDTCAccess,
						  networkDTCAccessAdmin, networkDTCAccessClients, networkDTCAccessInbound,
						  networkDTCAccessOutBound, networkDTCAccessTip, networkDTCAccessTransactions, XATransactions
		}
		$DTCCIDs = {
			New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null;
			Get-ItemProperty -Path HKCR:\CID\*\Description |
			Select-Object @{ l = 'Data'; e = { $_.'(default)' } }, @{ l = 'CID'; e = { $_.PSParentPath.split('\')[-1] } }
			Remove-PSDrive -Name HKCR | Out-Null;
		}
	}
	PROCESS
	{
		ForEach ($Computer in $Computername)
		{
			$dtcservice = $null
			try
			{
				Write-Verbose "Getting DTC on $computer via WinRM"
				$dtcservice = Get-Ciminstance -ComputerName $Computer -Query $query -ErrorAction Stop |
				Select-Object PSComputerName, DisplayName, State, status, StartMode, StartName
			}
			catch
			{
				try
				{
					Write-Verbose "Failed To get DTC via WinRM. Getting DTC on $computer via DCom"
					$SessionParams = @{ }
					$SessionParams.ComputerName = $Computer
					$SessionParams.SessionOption = (New-CimSessionOption -Protocol Dcom)
					$Session = New-CimSession @SessionParams
					$dtcservice = Get-Ciminstance -CimSession $Session -Query $query -ErrorAction Stop |
					Select-Object PSComputerName, DisplayName, State, status, StartMode, StartName
				}
				catch
				{
					Write-Warning "Can't connect to CIM on $Computer"
				}
			}
			$reg = $CIDs = $null
			$CIDHash = @{ }
			try
			{
				Write-Verbose "Getting Registry Values on $Computer"
				$reg = Invoke-Command -ComputerName $Computer -ScriptBlock $DTCSecurity -ErrorAction Stop
				$CIDs = Invoke-Command -ComputerName $Computer -ScriptBlock $DTCCIDs -ErrorAction Stop
				foreach ($key in $CIDs) { $CIDHash.Add($key.Data, $key.CID) }
			}
			catch
			{
				Write-Warning "Can't connect to registry on $Computer"
			}
			if ($dtcservice)
			{
				[PSCustomObject]@{
					ComputerName = $dtcservice.PSComputerName
					DTCServiceName = $dtcservice.DisplayName
					DTCServiceState = $dtcservice.State
					DTCServiceStatus = $dtcservice.Status
					DTCServiceStartMode = $dtcservice.StartMode
					DTCServiceAccount = $dtcservice.StartName
					DTCCID_MSDTC = $CIDHash['MSDTC']
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
					XATransactions = $reg.XATransactions
				}
			}
		}
	}
	END { }
}