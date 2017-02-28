Function Remove-DbaDatabase
{
<#
.SYNOPSIS
Removes the hell out of a database - with some prompts.

.DESCRIPTION
Tries a bunch of different ways to remove a database or two or more.

.PARAMETER SqlServer
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Databases
The database name to remove or an array of database names eg $Databases = 'DB1','DB2','DB3'

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
Tags: Delete

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

.LINK
https://dbatools.io/Remove-DbaDatabase

.EXAMPLE 


#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[parameter(Mandatory = $false)]
		[object]$SqlCredential
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		
		foreach ($instance in $SqlInstance)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			$inputobject = $server.Databases | Where-Object { $_.Name -in $databases }
			
			
			if ($dbname -notmatch "[")
			{
				$dbname = "[$dbname]"
			}
			
			
			try
			{
				$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
				$server.KillDatabase($dbname)
				$server.Refresh()
			}
			catch
			{
				try
				{
					$null = $server.ConnectionContext.ExecuteNonQuery("DROP DATABASE $escapedname")
					return "Successfully dropped $dbname on $($server.name)"
				}
				catch
				{
					try
					{
						$server.databases[$dbname].Drop()
						$server.Refresh()
						return "Successfully dropped $dbname on $($server.name)"
					}
					catch
					{
						return $_
					}
				}
			}
		}
	}
}