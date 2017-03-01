Function Test-DbaValidLogin
{
<#
.SYNOPSIS 
Test-DbaValidLogin Finds any logins on SQL instance that are AD logins with either disabled AD user accounts or ones that nolonger exist

.DESCRIPTION
The purpose of this function is to find SQL Server logins that are used by active directory users that are either disabled or removed from the domain. It allows you to 
keep your logins accurate and up to date by removing accounts that are no longer needed. 

.PARAMETER SQLServer
SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

.PARAMETER Logins
Filters the results to only the login you wish 

.PARAMETER Exclude
Excludes any login you pass into it from the results.

.PARAMETER FilterBy
By default the function returns both Logins and Groups. you can use the FilterBy parameter to only return Groups (GroupsOnly) or Logins (LoginsOnly)

.PARAMETER ExcludeDomains
Bu default we tranverse all domains in the forest and all trusted domains. You can exclude domains by adding them to the ExcludeDomains

.PARAMETER Detailed
Returns a more detailed result, showing if the login on SQL Server is enabled or disabled and what type of account it is in AD 

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
Test-DbaValidLogin -SqlServer Dev01 -ExcludeDomains subdomain.ad.local

Tests all logins excluding any that are from the mydomain Domain

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[ValidateSet("LoginsOnly", "GroupsOnly")]
		[string]$FilterBy = "None",
		[string[]]$ExcludeDomains,
		[switch]$Detailed
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlLogins -SqlServer $SqlServer[0] -SqlCredential $SqlCredential -WindowsOnly } }
	
	BEGIN
	{
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
			$alldomains = $domains = @()
			$currentforest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
			$alldomains += $currentforest.Domains.name | Where-Object { $_ -notin $excludedomains }
			
			$cd = $currentforest.Domains | Where-Object { $_.name -notin $excludedomains }
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
		
		foreach ($domain in $alldomains)
		{
			try
			{
				$dn = ConvertTo-Dn $domain
				$translate = New-Object -comObject NameTranslate
				$reflection = $translate.GetType()
				$reflection.InvokeMember("Init", "InvokeMethod", $Null, $translate, (3, $Null))
				$reflection.InvokeMember("Set", "InvokeMethod", $Null, $translate, (1, $dn))
				$netbios = $reflection.InvokeMember("Get", "InvokeMethod", $Null, $translate, 3).Trim("\")
				
				$domains += [pscustomobject]@{
					DNS = $domain
					DN = $dn
					NetBios = $netbios
					LDAP = "LDAP://" + $netbios + "/" + $DN
				}
			}
			catch
			{
				Write-Warning "Removing $domain from domain list"
			}
		}
		
		$Logins = $psboundparameters.Logins
		$Exclude = $psboundparameters.Exclude
	}
	
	PROCESS
	{
		foreach ($instance in $sqlserver)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
				Write-Verbose "Connected to: $instance"
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			if ($Logins)
			{
				$windowslogins = $server.Logins | Where-Object { $Logins -contains $_.Name }
			}
			else
			{
				switch ($FilterBy)
				{
					"LoginsOnly"
					{
						Write-Verbose "connecting to logins"
						$windowslogins = $server.Logins | Where-Object { $_.LoginType -eq 'WindowsUser' }
						$windowslogins = $windowslogins | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($SqlServer) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
					}
					"GroupsOnly"
					{
						Write-Verbose "connecting to groups"
						$windowsGroups = $server.Logins | Where-Object { $_.LoginType -eq 'WindowsGroup' }
						$windowsGroups = $windowsGroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name -notmatch $SqlServer -and $_.Name.StartsWith("BUILTIN") -eq $false }
					}
					"None"
					{
						Write-Verbose  "connecting to both logins and groups"
						$allwindowsloginsgroups = $server.Logins | Where-Object { $_.LoginType -eq 'WindowsUser' -or $_.LoginType -eq 'WindowsGroup' }
						$windowslogins = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsUser' }
						$windowslogins = $windowslogins | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($SqlServer) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
						$windowsGroups = $allwindowsloginsgroups | Where-Object { $_.LoginType -eq 'WindowsGroup' }
						$windowsGroups = $windowsGroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name -notmatch $SqlServer.Split("\\")[0] -and $_.Name.StartsWith("BUILTIN") -eq $false }
					}
					
				}
			}
			
			if ($exclude)
			{
				$windowslogins = $windowslogins | Where-Object { $Logins -notcontains $_.Name }
				$windowsGroups = $windowsGroups | Where-Object { $Logins -notcontains $_.Name }
				
			}
			
			foreach ($login in $windowslogins)
			{
				
				$adlogin = $login.Name
				Write-Verbose "Parsing Login $adlogin"
				$domain, $username = $adlogin.Split("\")
				$filter = "(&(objectCategory=User)(sAMAccountName=$username))" # won't work with groups			
				Write-Verbose $filter
				
				if ($env:USERDOMAIN -eq $domain)
				{
					$searcher = New-Object System.DirectoryServices.DirectorySearcher
					$searcher.Filter = $filter
				}
				else
				{
					$LDAP = ($domains | Where-Object NetBios -eq $domain).LDAP
					$ad = New-Object System.DirectoryServices.DirectoryEntry $LDAP
					$searcher = New-Object System.DirectoryServices.DirectorySearcher
					$searcher.SearchRoot = $ad
					$searcher.Filter = $filter
				}
				try
				{
					$founduser = $searcher.findOne()
				}
				catch
				{
					Write-Warning "AD Searcher Error for $username"
				}
				$value = $founduser.Properties.useraccountcontrol
				
				$enabled = $exists = $false
				$adlogindetails = 'unknown'
				
				## values from  http://www.netvision.com/ad_useraccountcontrol.php
				switch ($value)
				{
					512      {
						$enabled = $true
						$adlogindetails = 'Enabled Account'
					}
					514      {
						$enabled = $false
						$adlogindetails = 'Disabled Account'
					}
					544      {
						$enabled = $true
						$adlogindetails = 'Enabled, Password Not Required'
					}
					546      {
						$enabled = $false
						$adlogindetails = 'Disabled, Password Not Required'
					}
					66048    {
						$enabled = $true
						$adlogindetails = 'Enabled, Password Doesnt Expire'
					}
					66050    {
						$enabled = $false
						$adlogindetails = 'Disabled, Password Doesnt Expire'
					}
					66080    {
						$enabled = $true
						$adlogindetails = 'Enabled, Password Doesnt Expire & Not Required'
					}
					66082    {
						$enabled = $false
						$adlogindetails = 'Disabled, Password Doesnt Expire & Not Required'
					}
					262656   {
						$enabled = $true
						$adlogindetails = 'Enabled, Smartcard Required'
					}
					262658   {
						$enabled = $false
						$adlogindetails = 'Disabled, Smartcard Required'
					}
					262688   {
						$enabled = $true
						$adlogindetails = 'Enabled, Smartcard Required, Password Not Required'
					}
					262690   {
						$enabled = $false
						$adlogindetails = 'Disabled, Smartcard Required, Password Not Required'
					}
					328192   {
						$enabled = $true
						$adlogindetails = 'Enabled, Smartcard Required, Password Doesnt Expire'
					}
					328194   {
						$enabled = $false
						$adlogindetails = 'Disabled, Smartcard Required, Password Doesnt Expire'
					}
					328224   {
						$enabled = $true
						$adlogindetails = 'Enabled, Smartcard Required, Password Doesnt Expire & Not Required'
					}
					328226   {
						$enabled = $false
						$adlogindetails = 'Disabled, Smartcard Required, Password Doesnt Expire & Not Required'
					}
					590336
					{
						$enabled = $true
						$adlogindetails = 'Enabled, User Cannot Change Password & Password Never Expires'
					}
					$null
					{
						$exists = $true
					}
					default
					{
						Write-Verbose "unknown value passed from useraccountcontrol Server: $sqlServer Login: $username Domain: $domain Value: $value"
						$exists = 'Unknown'
						$enabled = 'Unknown'
					}
				}
				
				if ($Detailed)
				{
					[PSCustomObject]@{
						Server = $server.Name
						Domain = $domain
						Login = $username
						Type = "User"
						Found = $exists -ne $true
						Enabled = $enabled
						DisabledInSQLServer = $login.IsDisabled
						ADLoginDetails = $adlogindetails
					}
				}
				else
				{
					[PSCustomObject]@{
						Server = $server.Name
						Domain = $domain
						Login = $username
						Type = "User"
						Found = $exists -ne $true
						Enabled = $enabled
					}
				}
			} # foreach login
			
			foreach ($login in $windowsGroups)
			{
				$adlogin = $login.Name
				Write-Verbose "Parsing Group $adlogin"
				$domain, $username = $adlogin.Split("\")
				$filter = "(&(objectCategory=group)(sAMAccountName=$username))" # won't work with groups			
				Write-Verbose $filter
				
				if ($env:USERDOMAIN -eq $domain)
				{
					$searcher = New-Object System.DirectoryServices.DirectorySearcher
					$searcher.Filter = $filter
				}
				else
				{
					$LDAP = ($domains | Where-Object NetBios -eq $domain).LDAP
					$ad = New-Object System.DirectoryServices.DirectoryEntry $LDAP
					$searcher = New-Object System.DirectoryServices.DirectorySearcher($ad)
					$searcher.SearchRoot = $ad
					$searcher.Filter = $filter
				}
				try
				{
					$founduser = $searcher.findOne()
				}
				catch
				{
					Write-Warning "AD Searcher Error for $username on $SqlServer"
				}
				
				$enabled = $exists = $false
				
				if ($founduser)
				{
					$enabled = $true
				}
				else
				{
					$exists = $true
				}
				if ($Detailed)
				{
					[PSCustomObject]@{
						Server = $server.Name
						Domain = $domain
						Login = $username
						Type = "Group"
						Found = $exists -ne $true
						Enabled = $enabled
						DisabledInSQLServer = $login.IsDisabled
						ADLoginDetails = 'AD group'
					}
				}
				else
				{
					[PSCustomObject]@{
						Server = $server.Name
						Domain = $domain
						Login = $username
						Type = "Group"
						Found = $exists -ne $true
						Enabled = $enabled
					}
				}
			} # foreach group
		}
	}
}
