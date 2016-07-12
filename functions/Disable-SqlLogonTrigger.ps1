Function Disable-SqlLogonTrigger
{
<#
.SYNOPSIS


.DESCRIPTION

	
.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER TriggerName
The name of a specific logon trigger to disable.

.PARAMETER DisableAll
Disable all logon triggers not shipped by Microsoft.

.NOTES 
Original Author: Daniel Alexander (@dansqldba)
Further reading: SQL Logon Triggers         - https://msdn.microsoft.com/en-us/library/bb326598.aspx
                 Dedicated Admin Connection - https://msdn.microsoft.com/en-us/library/ms189595.aspx

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
https://dbatools.io/Disable-SqlLogonTrigger

.EXAMPLE   (Try to have at least 3 for more advanced commands)
Disable-SqlLogonTrigger -SqlServer sqlserver2014a -TriggerName sometrigger

Disables the specified trigger

.EXAMPLE   
Disable-SqlLogonTrigger -SqlServer sqlserver2014a -DisableAll

Disables all user logon triggers, Microsoft shipped triggers are untouched.

#>
	
	# This is a sample. Please continue to use aliases for discoverability. Also keep the [object] type for sqlserver.
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$TriggerName,
        [switch]$DisableAll
	)
	DynamicParam { if ($sqlserver) { return (Get-ParamSqlServerTriggers -SqlServer $sqlserver -SqlCredential $SourceSqlCredential) } }
		
	BEGIN
	{
		# Create your supporting functions here. Check SharedFunctions.ps1 first to see if it already has what you need.
		
		Function Do-Something {
			# Remember that the whole .ps1 shares variables, so
			# you do not need (though you can) to specify the params again
			
			return $sourceserver.name
			
		}
		
		Write-Output "Attempting to connect to SQL Server.."
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
        $dacenabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue

        # Does your script use something only supported in specific versions? Do a check.
        # da: SQL Logon triggers might only be supported in 2005 SP2 and above. Worth a check?
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Collection Sets are only supported in SQL Server 2008 and above. Quitting."
		}
		
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
        # da: What does this mean?
		$Logins = $psboundparameters.Logins
	}
	
	PROCESS
	{
		foreach ($login in $logins)
		{
			# Use SMO as much as possible. Using T-SQL is generally an exception.		
			if ($login.LoginType -eq "WindowsUser" -or $login.LoginType -eq "WindowsGroup")
			{				
				If ($Pscmdlet.ShouldProcess($source, "Doing something to that"))
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
			
			# SqlConnections are built into the SMO connections already. You can either use the current context or a specific database
			
			# ExecuteScalar returns 1 row with 1 column
			$hashedpass = $sourceserver.ConnectionContext.ExecuteScalar($sql)
			
			# Need to execute something in a specific database and have it return a datatable?
			$hashedpassdt = $sourceserver.databases['myspecificdb'].ExecuteWithResults($sql)
			
			# Use if you find yourself having a super long if/else, you may need to use continue instead.
			# Need to write a warning?
			
			if ($whatever -eq "we should just skip this, actually")
			{
					Write-Warning "$($login.LoginType) logins not supported. $($login.name) skipped."
					continue
			}
				
			# Don't forget the version is stored in the SMO server object
			
			if ($sourceserver.versionMajor -ge 9)
			{
				# This script can support 2000, but this portion will only work in 2005 and above.
				
			}
			
			# Oh, also, if you find yourself doing a bunch of elseif, remember how awesome switch is
			switch ($sourceserver.VersionMajor)
			{
				9 { $sqlversion = "SQL Server 2005 $servicePack" }
				10 {
					if ($sourceserver.VersionMinor -eq 0)
					{
						$sqlversion = "SQL Server 2008 $servicePack"
					}
					else
					{
						$sqlversion = "SQL Server 2008 R2 $servicePack"
					}
				}
				11 { $sqlversion = "SQL Server 2012 $servicePack" }
				12 { $sqlversion = "SQL Server 2014 $servicePack" }
				13 { $sqlversion = "SQL Server 2016 $servicePack" }
				default
				{
					Write-Warning "SQL version not currently supported."
					continue
				}
			}
		}
	}
	
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			Write-Output "SQL Logon Trigger disabled"
			$sourceserver.ConnectionContext.Disconnect()
		}
	}
}