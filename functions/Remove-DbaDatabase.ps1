Function Remove-DbaDatabase
{
<#
.SYNOPSIS
Drops a database, hopefully even the really stuck ones.

.DESCRIPTION
Tries a bunch of different ways to remove a database or two or more.

.PARAMETER SqlInstance
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

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Delete

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

.LINK
https://dbatools.io/Remove-DbaDatabase

.EXAMPLE 
Remove-DbaDatabase -SqlInstance sql2016 -Databases containeddb

Prompts then removes the database containeddb on SQL Server sql2016
	
.EXAMPLE 
Remove-DbaDatabase -SqlInstance sql2016 -Databases containeddb, mydb
	
Prompts then removes the databases containeddb and mydb on SQL Server sql2016
	
.EXAMPLE 
Remove-DbaDatabase -SqlInstance sql2016 -Databases containeddb -Confirm:$false

Does not prompt and swiftly removes containeddb on SQL Server sql2016
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[parameter(Mandatory = $false)]
		[object]$SqlCredential,
		[switch]$Silent
	)
	
	DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		
		if (-not $databases)
		{
			Stop-Function -Message "You must select one or more databases to drop"
		}
	}
	
	PROCESS
	{
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance)
		{
			try
			{
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			$databases = $server.Databases | Where-Object { $_.Name -in $databases }
			
			foreach ($db in $databases)
			{
				try
				{
					if ($Pscmdlet.ShouldProcess("$db on $server", "KillDatabase"))
					{
						$server.KillDatabase($db.name)
						$server.Refresh()
						
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database = $db.name
							Status = "Dropped"
						}
					}
				}
				catch
				{
					try
					{
						if ($Pscmdlet.ShouldProcess("$db on $server", "alter db set single_user with rollback immediate then drop"))
						{
							$null = $server.ConnectionContext.ExecuteNonQuery("alter database $db set single_user with rollback immediate; drop database $db")
							
							[pscustomobject]@{
								ComputerName = $server.NetName
								InstanceName = $server.ServiceName
								SqlInstance = $server.DomainInstanceName
								Database = $db.name
								Status = "Dropped"
							}
						}
					}
					catch
					{
						try
						{
							if ($Pscmdlet.ShouldProcess("$db on $server", "SMO drop"))
							{
								$server.databases[$dbname].Drop()
								$server.Refresh()
								
								[pscustomobject]@{
									ComputerName = $server.NetName
									InstanceName = $server.ServiceName
									SqlInstance = $server.DomainInstanceName
									Database = $db.name
									Status = "Dropped"
								}
							}
						}
						catch
						{
							Write-Message -Level Verbose -Message "Could not drop database $db on $server"
							
							[pscustomobject]@{
								ComputerName = $server.NetName
								InstanceName = $server.ServiceName
								SqlInstance = $server.DomainInstanceName
								Database = $db.name
								Status = $_
							}
						}
					}
				}
			}
		}
	}
}