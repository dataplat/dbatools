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

.PARAMETER Type
You *should* always know what you are asking for. Please pass in Computer,Group or User to help speeding up the search

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
				Stop-Function -Message "You need to pass ADObject in DOMAIN\object format" -Continue -Silent $Silent -Target $ADObj
			}
			$Domain, $obj = $Splitted
			try {
				$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domain)
				$found = $searchClass::FindByIdentity($ctx, 'sAMAccountName', $obj)
				$found
			} catch {
				Stop-Function -Message "Errors trying to connect to the domain $Domain $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $ADObj
			}
		}
	}
}

