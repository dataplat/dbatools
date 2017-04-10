#ValidationTags#FlowControl,Pipeline#
Function Get-DbaADObject
{
<#
.SYNOPSIS
Get-DbaADObject tries to facilitate searching AD with dbatools, which ATM can't require AD cmdlets.

.DESCRIPTION
As working with multiple domains, forests, ldap filters, partitions, etc is quite hard to grasp, let's try to do "the right thing" here and
facilitate everybody's work with it. It either returns the exact matched result or None if it isn't found. You can inspect the raw object
calling GetUnderlyingObject() on the returned object.

.PARAMETER ADObject
Pass in both the domain and the login name in NETBIOSDomain\sAMAccountName format (the one everybody is accustomed to)
You can also pass a UserPrincipalName@Domain format with the correct IdentityType.
For any other format, please beware that the domain part must always be specified (either before the slash or after the at symbol)

.PARAMETER Type
You *should* always know what you are asking for. Please pass in Computer,Group or User to help speeding up the search

.PARAMETER IdentityType
By default objects are searched using sAMAccountName format, here you can pass different representation that need to match the passed in ADObject

.PARAMETER Credential
Use this credential to connect to the domain and search for the needed ADObject. If not passed, uses the current process' one.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Author: Niphlod, https://github.com/niphlod

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Get-DbaADObject -ADObject "contoso\ctrlb" -Type User

Seaches in the contoso domain for a ctrlb user

.EXAMPLE
Get-DbaADObject -ADObject "ctrlb@contoso.com" -Type User -IdentityType UserPrincipalName

Seaches in the contoso domain for a ctrlb user using the UserPrincipalName format

.EXAMPLE
Get-DbaADObject -ADObject "contoso\sqlcollaborative" -Type Group

Seaches in the contoso domain for a sqlcollaborative group

.EXAMPLE
Get-DbaADObject -ADObject "contoso\sqlserver2014$" -Type Group

Seaches in the contoso domain for a sqlserver2014 computer (remember the ending $ for computer objects)

.EXAMPLE
Get-DbaADObject -ADObject "contoso\ctrlb" -Type User -Silent

Seaches in the contoso domain for a ctrlb user, suppressing all error messages and throw exceptions that can be caught instead

#>
	[CmdletBinding()]
	Param (
		[string[]]$ADObject,
		[ValidateSet("User","Group","Computer")]
		[string]$Type,

		[ValidateSet("DistinguishedName","Guid","Name","SamAccountName","Sid","UserPrincipalName")]
		[string]$IdentityType = "SamAccountName",

		[System.Management.Automation.Credential()]$Credential,
		[switch]$Silent
	)
	BEGIN {
		try {
			Add-Type -AssemblyName System.DirectoryServices.AccountManagement
		} catch {
			Stop-Function -Message "Failed to load the required module $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_
			return
		}
		switch ($Type) {
			"User" {
				$searchClass = [System.DirectoryServices.AccountManagement.UserPrincipal]
			}
			"Group" {
				$searchClass = [System.DirectoryServices.AccountManagement.GroupPrincipal]
			}
			"Computer" {
				$searchClass = [System.DirectoryServices.AccountManagement.ComputerPrincipal]
			}
			default {
				$searchClass = [System.DirectoryServices.AccountManagement.Principal]
			}
		}
	}
	PROCESS {
		if (Test-FunctionInterrupt) { return }
		foreach($ADObj in $ADObject) {
			$Splitted = $ADObj.Split("\")
			if ($Splitted.Length -ne 2) {
				$Splitted = $ADObj.Split("@")
				if ($Splitted.Length -ne 2) {
					Stop-Function -Message "You need to pass ADObject either DOMAIN\object or object@domain format" -Continue -Silent $Silent
				} else {
					$obj, $Domain = $AdObj, $Splitted[1]
				}
			} else {
				$Domain, $obj = $Splitted
			}
			try {
				if ($Credential) {
					$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domain, $Credential.UserName, $Credential.GetNetworkCredential().Password)
				} else {
					$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domain)
				}
				$found = $searchClass::FindByIdentity($ctx, $IdentityType, $obj)
				$found
			} catch {
				Stop-Function -Message "Errors trying to connect to the domain $Domain $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $ADObj
			}
		}
	}
}

