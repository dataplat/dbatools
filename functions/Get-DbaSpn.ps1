function Get-DbaSpn
{
<#
.SYNOPSIS
Returns a list of set service principal names for a given computer/AD account

.DESCRIPTION
Get a list of set SPNs. SPNs are set at the AD account level. You can either retrieve set SPNs for a computer, or any SPNs set for
a given active directry account. You can query one, or both. You'll get a list of every SPN found for either search term.

.PARAMETER ComputerName
The servers you want to return set SPNs for.

.PARAMETER AccountName
The accounts you want to retrieve set SPNs for.

.PARAMETER Credential
User credential to connect to the remote servers or active directory. This is a required parameter.

.NOTES 
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
        [string[]]$ComputerName,
        [Parameter(Mandatory = $false)]
		[string[]]$AccountName,
		[Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )
	process
	{
		if (!$ComputerName -and !$AccountName)
		{
			$ComputerName = $env:computername
			$AccountName = "$env:USERDOMAIN\$env:USERNAME"
		}
		
		if ($ComputerName)
		{
			if ($ComputerName[0].EndsWith('$'))
			{
				$AccountName = $ComputerName
				$ComputerName = $null
			}
		}
		
		ForEach ($account in $AccountName)
		{
			$ogaccount = $account
            if ($account -like "*\*") {
                Write-Verbose "Account name ($account) provided in in domain\user format, stripping out domain info."
                $account = ($account.split("\"))[1]
            }
            if ($account -like "*@*") {
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
		
		
		foreach ($server in $ComputerName)
		{
			Write-Verbose "Getting SQL Server SPN for $server"
			$spns = Test-DbaSpn -ComputerName $server -Credential $Credential
			
			$sqlspns = 0
			$spncount = $spns.count
			Write-Verbose "Calculated $spncount SQL SPN entries that should exist for $server"
			foreach ($spn in $spns | Where-Object { $_.IsSet -eq $true })
			{
				$sqlspns++
                [pscustomobject] @{
					Input = $server
					AccountName = $spn.InstanceServiceAccount
					ServiceClass = "MSSQLSvc"
					Port = $spn.Port
					SPN = $spn.RequiredSPN
                }
			}
			Write-Verbose "Found $sqlspns set SQL SPN entries for $server"
		}
	}
}