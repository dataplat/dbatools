function Get-DbaSpn
{
<#
.SYNOPSIS
Returns a list of set service principal names for a given computer/AD account

.DESCRIPTION
Get a list of set SPNs. SPNs are set at the AD account level. You can either retrieve set SPNs for a computer, or any SPNs set for
a given active directry account. You can query one, or both. You'll get a list of every SPN found for either search term.

.PARAMETER ComputerName
The servers you want to return set SPNs for. This is defaulted automatically to localhost.

.PARAMETER AccountName
The accounts you want to retrieve set SPNs for.

.PARAMETER Credential
User credential to connect to the remote servers or active directory. This is a required parameter.
	
.PARAMETER ByAccount
Shows all SPNs registered by the specified AccountName otherwise, only results will be shown for the specified ComputerName (which is localhost by default)

.NOTES
Tags: SPN
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com
	
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaSpn

.EXAMPLE
Get-DbaSpn -ServerName SQLSERVERA -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found

.EXAMPLE
Get-DbaSpn -AccountName doamain\account -Credential (Get-Credential)

Returns a custom object with SearchTerm (domain account) and the SPNs that were found

.EXAMPLE
Get-DbaSpn -ServerName SQLSERVERA,SQLSERVERB -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found for multiple computers
#>
    [cmdletbinding()]
	param (
        [Parameter(Mandatory = $false,ValueFromPipeline = $true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory = $false)]
		[string[]]$AccountName,
		[switch]$ByAccount,
		[Parameter(Mandatory = $false)]
        [PSCredential]$Credential
	)
	begin
	{
		Function Process-Account ($AccountName, $ByAccount) {
			
			ForEach ($account in $AccountName)
			{
				$ogaccount = $account
				if ($account -like "*\*")
				{
					Write-Verbose "Account name ($account) provided in in domain\user format, stripping out domain info."
					$account = ($account.split("\"))[1]
				}
				if ($account -like "*@*")
				{
					Write-Verbose "Account name ($account) provided in in user@domain format, stripping out domain info."
					$account = ($account.split("@"))[0]
				}
				
				$root = ([ADSI]"LDAP://RootDSE").defaultNamingContext
				$adsearch = New-Object System.DirectoryServices.DirectorySearcher
				
				if ($Credential)
				{
					$domain = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root), $($Credential.UserName), $($Credential.GetNetworkCredential().password)
				}
				else
				{
					$domain = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root)
				}
				
				$adsearch.SearchRoot = $domain
				$adsearch.Filter = $("(&(samAccountName={0}))" -f $account)
				
				Write-Verbose "Looking for account $account..."
				
				try
				{
					$Result = $adsearch.FindOne()
				}
				catch
				{
					Write-Warning "AD lookup failure. This may be because the hostname ($computer) was not resolvable within the domain ($domain) or the SQL Server service account ($serviceaccount) couldn't be found in domain."
					continue
				}
				
				$properties = $result.Properties
				
				foreach ($spn in $result.Properties.serviceprincipalname)
				{
					if ($spn -match "\:")
					{
						try
						{
							$port = [int]($spn -Split "\:")[1]
						}
						catch
						{
							$port = $null
						}
						if ($spn -match "\/")
						{
							$serviceclass = ($spn -Split "\/")[0]
						}
					}
					[pscustomobject] @{
						Input = $ogaccount
						AccountName = $ogaccount
						ServiceClass = "MSSQLSvc" # $serviceclass
						Port = $port
						SPN = $spn
					}
				}
			}
			continue
		}
	}
	
	process
	{	
		foreach ($computer in $ComputerName)
		{
			if ($computer)
			{
				if ($computer.EndsWith('$'))
				{
					Write-Verbose "$computer is an account name. Processing as account."
					Process-Account -AccountName $computer -ByAccount:$true
					continue
				}
			}
			
			Write-Verbose "Getting SQL Server SPN for $computer"
			$spns = Test-DbaSpn -ComputerName $computer -Credential $Credential
			
			$sqlspns = 0
			$spncount = $spns.count
			Write-Verbose "Calculated $spncount SQL SPN entries that should exist for $computer"
			foreach ($spn in $spns | Where-Object { $_.IsSet -eq $true })
			{
				$sqlspns++
				
				if ($accountName)
				{
					if ($accountName -eq $spn.InstanceServiceAccount)
					{
						[pscustomobject] @{
							Input = $computer
							AccountName = $spn.InstanceServiceAccount
							ServiceClass = "MSSQLSvc"
							Port = $spn.Port
							SPN = $spn.RequiredSPN
						}
					}
				}
				else
				{
					[pscustomobject] @{
						Input = $computer
						AccountName = $spn.InstanceServiceAccount
						ServiceClass = "MSSQLSvc"
						Port = $spn.Port
						SPN = $spn.RequiredSPN
					}
				}
			}
			Write-Verbose "Found $sqlspns set SQL SPN entries for $computer"
		}
		
		if ($AccountName)
		{
			foreach ($account in $AccountName)
			{
				Process-Account -AccountName $account -ByAccount:$ByAccount
			}
		}
	}
}
