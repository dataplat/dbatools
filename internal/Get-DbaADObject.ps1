Function Get-DbaADObject
{
<#
.SYNOPSIS
Get-DbaADObject tries to facilitate searching AD with dbatools, which ATM can't require AD cmdlets.

.DESCRIPTION
As working with multiple domains, forests, ldap filters, partitions, etc is quite hard to grasp, let's try to do "the right thing" here and
facilitate everybody's work with it.

.PARAMETER ADObject
ATM it takes something in the format "DOMAIN\LdapFilter" but let's see how to make it better

.NOTES
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/
Author: Chrissy LeMaire (@cl), netnerds.net
Author: Niphlod, https://github.com/niphlod

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Get-DbaADObject -ADObject "contoso\(&(objectCategory=User)(sAMAccountName=ctrlb))"

Seaches in the contoso domain for a ctrlb sAMAccountName

#>
	[CmdletBinding()]
	Param (
		[string[]]$ADObject
	)

	BEGIN {
		function ConvertTo-Dn ([string]$dns)
		{
			$array = $dns.Split(".")
			for ($x = 0; $x -lt $array.Length; $x++)
			{
				if ($x -eq ($array.Length - 1)) { $separator = "" }
				else { $separator = "," }
				[string]$dn += "DC=" + $array[$x] + $separator
			}
			return $dn
		}
		try
		{
			$alldomains = @()
			$currentforest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
			$alldomains += $currentforest.Domains.name

			$cd = $currentforest.Domains
		}
		catch
		{
			Write-warning "No Active Directory domains Found."
			break
		}
		foreach ($domain in $cd)
		{
			try
			{
				$alldomains += ($Domain.GetAllTrustRelationships()).TargetName
			}
			catch
			{
				$alldomains = $alldomains | Where-Object { $_ -ne $domain.name }
				Write-Warning "Couldn't contact $domain"
			}
		}

		$alldomains = $alldomains | Select-Object -Unique

		# should leverage "process" cache for this, maybe @fred can help
		$script:domains = @()

		function Resolve-ExpensiveDomain([string]$NetBiosName) {
			foreach ($domain in $alldomains) {
				if ($script:domains.DNS -contains $domain) { continue }
				try {
					$dn = ConvertTo-Dn $domain
					$translate = New-Object -comObject NameTranslate
					$reflection = $translate.GetType()
					$reflection.InvokeMember("Init", "InvokeMethod", $Null, $translate, (3, $Null)) | out-null
					$reflection.InvokeMember("Set", "InvokeMethod", $Null, $translate, (1, $dn)) | out-null
					$netbios = $reflection.InvokeMember("Get", "InvokeMethod", $Null, $translate, 3).Trim("\")
					$script:domains += [pscustomobject]@{
						DNS = $domain
						DN = $dn
						NetBios = $netbios
						LDAP = "LDAP://" + $netbios + "/" + $DN
					}
					if ($NetBiosName -eq $netbios) {
						break
					}
				} catch {
					Write-Warning "Removing $domain from domain list"
				}
			}
		}

	}
	PROCESS {
		foreach($adobj in $ADObject) {
			$domain, $filter = $adobj.Split("\")
			if ($env:USERDOMAIN -eq $domain) {
				$searcher = New-Object System.DirectoryServices.DirectorySearcher
				$searcher.Filter = $filter
			} else {
				Resolve-ExpensiveDomain -NetBiosName $domain
				$LDAP = ($script:domains | Where-Object NetBios -eq $domain).LDAP
				$ad = New-Object System.DirectoryServices.DirectoryEntry $LDAP
				$searcher = New-Object System.DirectoryServices.DirectorySearcher
				$searcher.SearchRoot = $ad
				$searcher.Filter = $filter
			}
			try
			{
				$foundobject = $searcher.findAll()
			}
			catch
			{
				Write-Warning "AD Searcher Error for filter $filter"
			}
			$foundobject
		}
	}
}