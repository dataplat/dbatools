Function Test-DbaValidLogin
{
<#
.SYNOPSIS
Test-DbaValidLogin finds any logins on SQL instance that are AD logins with either disabled AD user accounts or ones that no longer exist

.DESCRIPTION
The purpose of this function is to find SQL Server logins that are used by active directory users that are either disabled or removed from the domain. It allows you to
keep your logins accurate and up to date by removing accounts that are no longer needed.

.PARAMETER SQLServer
SQL instance to check. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

.PARAMETER Logins
Filters the results to only the login you wish

.PARAMETER Exclude
Excludes any login you pass into it from the results.

.PARAMETER FilterBy
By default the function returns both Logins and Groups. you can use the FilterBy parameter to only return Groups (GroupsOnly) or Logins (LoginsOnly)

.PARAMETER IgnoreDomains
By default we traverse all domains in the forest and all trusted domains. You can exclude domains by adding them to the IgnoreDomains

.PARAMETER Detailed
Returns a more detailed result, showing if the login on SQL Server is enabled or disabled and what type of account it is in AD

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/
Author: Chrissy LeMaire (@cl), netnerds.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaValidLogin

.EXAMPLE
Test-DbaValidLogin -SqlServer Dev01

Tests all logins in the domain ran from (check $env:domain) that are either disabled or do not exist

.EXAMPLE
Test-DbaValidLogin -SqlServer Dev01 -FilterBy GroupsOnly -Detailed

Tests all Active directory groups that have logins on Dev01 returning a detailed view.

.EXAMPLE
Test-DbaValidLogin -SqlServer Dev01 -ExcludeDomains subdomain

Tests all logins excluding any that are from the subdomain Domain

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[ValidateSet("LoginsOnly", "GroupsOnly")]
		[string]$FilterBy = "None",
		[string[]]$IgnoreDomains,
		[switch]$Detailed,
		[switch]$Silent
	)

	DynamicParam { if ($SqlServer) { return Get-ParamSqlLogins -SqlServer $SqlServer[0] -SqlCredential $SqlCredential -WindowsOnly } }

	BEGIN
	{
		$Logins = $psboundparameters.Logins
		$Exclude = $psboundparameters.Exclude

		if($IgnoreDomains) {
			$IgnoreDomainsNormalized = $IgnoreDomains.toUpper()
			Write-Message -Message ("Excluding logins for domains " + ($IgnoreDomains -join ',')) -Level Verbose
		}
		if($Detailed) {
			Write-Message -Message "Detailed is deprecated and will be removed in dbatools 1.0" -Once "DetailedDeprecation" -Level Warning
		}
	}

	PROCESS
	{
		foreach ($instance in $sqlserver)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
				Write-Message -Message "Connected to: $instance" -Level Verbose
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance -InnerErrorRecord $_
			}


			# we can only validate AD logins
			$allwindowsloginsgroups = $server.Logins | Where-Object { $_.LoginType -in ('WindowsUser', 'WindowsGroup') }

			# we cannot validate local users
			$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($server.NetName) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
			if ($Logins)
			{
				$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $Logins -contains $_.Name }
			}
			if ($Exclude)
			{
				Write-verbose "excluding something"
				$allwindowsloginsgroups = $allwindowsloginsgroups | Where-Object { $Exclude -notcontains $_.Name }
			}
			switch ($FilterBy) {
				"LoginsOnly"
				{
					Write-Message -Message "Search restricted to logins" -Level Verbose
					$windowslogins = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsUser' }
				}
				"GroupsOnly"
				{
					Write-Message -Message "Search restricted to groups" -Level Verbose
					$windowsGroups = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsGroup' }
				}
				"None"
				{
					Write-Message -Message "Search both logins and groups" -Level Verbose
					$windowslogins = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsUser' }
					$windowsGroups = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsGroup' }
				}
			}
			foreach ($login in $windowslogins)
			{
				$adlogin = $login.Name
				$domain, $username = $adlogin.Split("\")
				if($domain.toUpper() -in $IgnoreDomainsNormalized) {
					Write-Message -Message "Skipping Login $adlogin" -Level Verbose
					continue
				}
				Write-Message -Message "Parsing Login $adlogin" -Level Verbose
				$exists = $false
				try
				{
					$u = Get-DbaADObject -ADObject $adlogin -Type User -Silent
					$founduser = $u.GetUnderlyingObject()
					if ($founduser) {
						$exists = $true
					}
				}
				catch
				{
					Write-Message -Message "AD Searcher Error for $username" -Level Warning
				}

				$value = $founduser.Properties.userAccountControl

				$enabled = $false
				$adlogindetails = 'Unknown'

				## values from  http://www.netvision.com/ad_useraccountcontrol.php
				switch ($value)
				{
					512      {
						$enabled = $true
						$adlogindetails = "Enabled Account"
					}
					514      {
						$enabled = $false
						$adlogindetails = "Disabled Account"
					}
					544      {
						$enabled = $true
						$adlogindetails = "Enabled, Password Not Required"
					}
					546      {
						$enabled = $false
						$adlogindetails = "Disabled, Password Not Required"
					}
					66048    {
						$enabled = $true
						$adlogindetails = "Enabled, Password Doesn't Expire"
					}
					66050    {
						$enabled = $false
						$adlogindetails = "Disabled, Password Doesn't Expire"
					}
					66080    {
						$enabled = $true
						$adlogindetails = "Enabled, Password Doesn't Expire & Not Required"
					}
					66082    {
						$enabled = $false
						$adlogindetails = "Disabled, Password Doesn't Expire & Not Required"
					}
					262656   {
						$enabled = $true
						$adlogindetails = "Enabled, Smartcard Required"
					}
					262658   {
						$enabled = $false
						$adlogindetails = "Disabled, Smartcard Required"
					}
					262688   {
						$enabled = $true
						$adlogindetails = "Enabled, Smartcard Required, Password Not Required"
					}
					262690   {
						$enabled = $false
						$adlogindetails = "Disabled, Smartcard Required, Password Not Required"
					}
					328192   {
						$enabled = $true
						$adlogindetails = "Enabled, Smartcard Required, Password Doesnt Expire"
					}
					328194   {
						$enabled = $false
						$adlogindetails = "Disabled, Smartcard Required, Password Doesnt Expire"
					}
					328224   {
						$enabled = $true
						$adlogindetails = "Enabled, Smartcard Required, Password Doesn't Expire & Not Required"
					}
					328226   {
						$enabled = $false
						$adlogindetails = "Disabled, Smartcard Required, Password Doesn't Expire & Not Required"
					}
					590336   {
						$enabled = $true
						$adlogindetails = "Enabled, User Cannot Change Password & Password Never Expires"
					}
					$null    {
						$enabled = "Unknown"
					}
					default  {
						Write-Message -Message "unknown value passed from useraccountcontrol Server: $sqlServer Login: $username Domain: $domain Value: $value" -Level Verbose
						$enabled = "Unknown"
					}
				}

				if ($Detailed)
				{
					[PSCustomObject]@{
						Server = $server.DomainInstanceName
						Domain = $domain
						Login = $username
						Type = "User"
						Found = $exists
						Enabled = $enabled
						DisabledInSQLServer = $login.IsDisabled
						ADLoginDetails = $adlogindetails
					}
				}
				else
				{
					[PSCustomObject]@{
						Server = $server.DomainInstanceName
						Domain = $domain
						Login = $username
						Type = "User"
						Found = $exists
						Enabled = $enabled
					}
				}
			}

			foreach ($login in $windowsGroups)
			{
				$adlogin = $login.Name
				$domain, $groupname = $adlogin.Split("\")
				if($domain.toUpper() -in $IgnoreDomainsNormalized) {
					Write-Message -Message "Skipping Login $adlogin" -Level Verbose
					continue
				}
				Write-Message -Message "Parsing Login $adlogin on $server" -Level Verbose
				$exists = $enabled = $false
				if ($true)
				{
					$founduser = Get-DbaADObject -ADObject $adlogin -Type Group -Silent
					if ($founduser) {
						$exists = $enabled = $true
					}
				}
				else
				{
					Write-Warning -Message "AD Searcher Error for $groupname on $server" -Level Warning
				}

				if ($Detailed)
				{
					[PSCustomObject]@{
						Server = $server.DomainInstanceName
						Domain = $domain
						Login = $groupname
						Type = "Group"
						Found = $exists
						Enabled = $enabled
						DisabledInSQLServer = $login.IsDisabled
						ADLoginDetails = 'AD group'
					}
				}
				else
				{
					[PSCustomObject]@{
						Server = $server.DomainInstanceName
						Domain = $domain
						Login = $groupname
						Type = "Group"
						Found = $exists
						Enabled = $enabled
					}
				}
			}
		}
	}
}