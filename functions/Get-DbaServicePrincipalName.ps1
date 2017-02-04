function Get-DbaServicePrincipalName
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
https://dbatools.io/Get-DbaServicePrincipalName

.EXAMPLE
Get-DbaServicePrincipalName -ServerName SQLSERVERA -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found

.EXAMPLE
Get-DbaServicePrincipalName -AccountName doamain\account -Credential (Get-Credential)

Returns a custom object with SearchTerm (domain account) and the SPNs that were found

.EXAMPLE
Get-DbaServicePrincipalName -ServerName SQLSERVERA,SQLSERVERB -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found for multiple computers
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ComputerName,
        [Parameter(Mandatory = $false)]
		[string[]]$AccountName,
		[Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )
	begin
	{
		if (!$ComputerName -and !$AccountName)
		{
			$ComputerName = "localhost"
			$AccountName = "$env:USERDOMAIN\$env:USERNAME"
		}
	}
	process
	{
		ForEach ($account in $AccountName)
		{
			$ogaccount = $account
            if ($account -like "*\*") {
                Write-Verbose "Account name ($account) provided in in domain\user format, stripping out domain info..."
                $account = ($account.split("\"))[1]
            }
            if ($account -like "*@*") {
                Write-Verbose "Account name ($account) provided in in user@domain format, stripping out domain info..."
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
            $Result = $adsearch.FindOne()
			
            foreach ($spn in $result.Properties.serviceprincipalname) {
                [pscustomobject] @{
                    Name = $ogaccount
                    SPN = $spn
                }
			}
		}
		
		foreach ($server in $ComputerName)
		{
			Write-Verbose "Getting SQL Server SPN for $server"
			$spns = Test-DbaServicePrincipalName -ComputerName $server -Credential $Credential
			
			Write-Verbose "Found $spns"
			foreach ($spn in $spns | Where-Object {$_.IsSet -eq $true}) {
                [pscustomobject] @{
                    Name = $server
                    SPN = $spn.RequiredSPN
                }
            }
        }
    }
}