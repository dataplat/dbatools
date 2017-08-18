Function Remove-DbaSpn
{
<#
.SYNOPSIS
Sets an SPN for a given service account in active directory, and also enables delegation to the same SPN

.DESCRIPTION
This function will connect to Active Directory and search for an account. If the account is found, it will attempt to remove the specified SPN. Once the SPN is removed, the function will also set delegation to that service. 

In order to run this function, the credential you provide must have write access to Active Directory.

Note: This function supports -WhatIf

.PARAMETER SPN
The SPN you want to remove

.PARAMETER ServiceAccount
The account you want the SPN remove from

.PARAMETER Credential
The credential you want to use to connect to Active Directory to make the changes

.PARAMETER Confirm
Turns confirmations before changes on or off
	
.PARAMETER WhatIf
Shows what would happen if the command was executed	
	
.NOTES
Tags: SPN
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Remove-DbaSpn

.EXAMPLE
Remove-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account

Connects to Active Directory and removes a provided SPN to the given account.

.EXAMPLE
Remove-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -Credential (Get-Credential)

Connects to Active Directory and removes a provided SPN to the given account. Uses alternative account to connect to AD.

.EXAMPLE
Test-DbaSpn -ComputerName sql2005 | Where { $_.isSet -eq $true } | Remove-DbaSpn -WhatIf
	
Connects to Active Directory and removes a provided SPN to the given account. Uses alternative account to connect to AD.


#>
	[cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	param (
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
		[Alias("RequiredSPN")]
		[string]$SPN,
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
		[Alias("InstanceServiceAccount", "AccountName")]
		[string]$ServiceAccount,
		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
		[pscredential]$Credential
	)
	
	process
	{
		$OGServiceAccount = $ServiceAccount
		if ($serviceaccount -like "*\*")
		{
			Write-Debug "Account provided in in domain\user format, stripping out domain info..."
			$serviceaccount = ($serviceaccount.split("\"))[1]
		}
		if ($serviceaccount -like "*@*")
		{
			Write-Debug "Account provided in in user@domain format, stripping out domain info..."
			$serviceaccount = ($serviceaccount.split("@"))[0]
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
		$adsearch.Filter = $("(&(samAccountName={0}))" -f $serviceaccount)
		Write-Verbose "Looking for account $serviceAccount..."
		$result = $adsearch.FindOne()
		
		#did we find the server account?
		
		if ($result -eq $null)
		{
			Write-Warning "The account specified for the SPN ($serviceAccount) does not exist on the domain"
			continue
		}
		else
		{
			# Cool! Remove an SPN
			
			$adentry = $result.GetDirectoryEntry()
			$delegate = $true
			
			if ($PSCmdlet.ShouldProcess("$spn", "Removing SPN for service account"))
			{
				try
				{
					$null = $adentry.Properties['serviceprincipalname'].Remove($spn)
					Write-Verbose "Remove SPN $spn for samaccount $serviceaccount"
					$adentry.CommitChanges()
					$set = $false
					$status = "Successfully removed SPN"
					$delegate = $true
				}
				catch
				{
					Write-Warning "Could not remove SPN. Error returned was: $_"
					$set = $true
					$status = "Failed to remove SPN"
					$delegate = $false
				}
				
				[pscustomobject]@{
					Name = $spn
					ServiceAccount = $OGServiceAccount
					Property = "servicePrincipalName"
					IsSet = $set
					Notes = $status
				}
			}
			
			if (!$delegate) { continue }
			
			# Don't forget delegation!
			$adentry = $result.GetDirectoryEntry()
			if ($PSCmdlet.ShouldProcess("$spn", "Removing delegation for service account for SPN"))
			{
				try
				{
					$null = $adentry.Properties['msDS-AllowedToDelegateTo'].Remove($spn)
					Write-Verbose "Removed kerberos delegation for $spn for samaccount $serviceaccount"
					$adentry.CommitChanges()
					$set = $false
					$status = "Successfully removed delegation"
				}
				catch
				{
					Write-Warning "Could not remove delegation. Error returned was: $_"
					$set = $true
					$status = "Failed to remove delegation"
				}
				
				[pscustomobject]@{
					Name = $spn
					ServiceAccount = $OGServiceAccount
					Property = "msDS-AllowedToDelegateTo"
					IsSet = $set
					Notes = $status
				}
			}
		}
	}
}
