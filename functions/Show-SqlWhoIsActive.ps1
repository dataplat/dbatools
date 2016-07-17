Function Show-SqlWhoIsActive
{
<#
.SYNOPSIS
Short description such as: Migrates SQL Policy Based Management Objects, including both policies and conditions.

.DESCRIPTION
Longer description such as: By default, all policies and conditions are copied. If an object already exist on the destination, it will be skipped unless -Force is used. 
	
The -Policies and -Conditions parameters are autopopulated for command-line completion and can be used to copy only specific objects.

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Force
If policies exists on destination server, it will be dropped and recreated.

.NOTES 
Original Author: You (@YourTwitter), yourblog.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Verb-SqlNoun
# I will create that link once we publish the function

.EXAMPLE   (Try to have at least 3 for more advanced commands)
Copy-SqlPolicyManagement -SqlServer sqlserver2014a

Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Copy-SqlPolicyManagement -SqlServer sqlserver2014a -SqlCredential $cred

Copies all policies and conditions from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlPolicyManagement -SqlServer sqlserver2014 -WhatIf

Shows what would happen if the command were executed.
	
.EXAMPLE   
Copy-SqlPolicyManagement -SqlServer sqlserver2014a -Policy 'xp_cmdshell must be disabled'

Copies only one policy, 'xp_cmdshell must be disabled' from sqlserver2014a to sqlcluster. No conditions are migrated.
	
#>
	
	# This is a sample. Please continue to use aliases for discoverability. Also keep the [object] type for sqlserver.
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$FilePath
	)
	
	# Please use dynamic parameters when possible. I've created most that you'll need in DynamicParams.ps1
	# dynamic parameters are the things that autocomplete when you tab. So in this case, it would be
	# -Logins <tab> and then it would fill in the logins from the SQL Server that you specified (-SqlServer)
	DynamicParam { if ($sqlserver) { return Get-ParamSqlLogins -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	# BEGIN is for private functions and starting connections. When using the pipeline, stuff in here will be executed first and only once.
	
	BEGIN
	{
		# Create your supporting functions here. Check SharedFunctions.ps1 first to see if it already has what you need.
		function Do-Something { }
		
		# By default, it's good to assume your function will likely be private. 
		# If you write any additional commands that certainly can use the private function in here, then add it to SharedFunctions.ps1 and let me know. 
		
		Write-Output "Attempting to connect to SQL Server.."
		
		# please continue to use these variable names for consistency
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
		$Logins = $psboundparameters.Logins
	}
	
	# PROCESS is for processing stuff. If using the pipeline, the things in here will be executed repeatedly.
	PROCESS
	{
		foreach ($login in $logins)
		{
			# Use SMO as much as possible. Using T-SQL is generally an exception.		
			if ($login.LoginType -eq "WindowsUser" -or $login.LoginType -eq "WindowsGroup")
			{
				# Making a change? ALWAYS surround it in ShouldProcess with a nice amount of detail.
				If ($Pscmdlet.ShouldProcess($source, "Doing somethign to that"))
				{
					try
					{
						Do-Something $that
					}
					catch
					{
						# Always use the Write-Exception shared function.
						Write-Exception $_
						throw "sometimes I throw, but sometimes I continue. I always use write-exception, though so the person can see details."
					}
				}
			}
			
		}
		
		# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
		END
		{
			$sourceserver.ConnectionContext.Disconnect()
			
			If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
			{
				Write-Output "SQL Login export to $FilePath complete"
				
			}
			
		}
	}