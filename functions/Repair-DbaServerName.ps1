Function Repair-DbaServerName
{
<#
.SYNOPSIS
Renames @@SERVERNAME to match with the Windows name.
	
.DESCRIPTION
When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

This command renames @@SERVERNAME to match with the Windows name. The new name is automatically determined. It does not matter if you use an alias to connect to the SQL instance.
		
If the automatically determiend new name matches the old name, the command will not run.
	
https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER Detailed
Specifies if the servername is updatable. If updatable -eq $false, it will return the reasons why.

.PARAMETER Force
By default, this command produces a ton of confirm prompts. Force bypasses many of these confirms, but not all.

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Repair-DbaServerName

.EXAMPLE
Repair-DbaServerName -SqlServer sql2014

Checks to see if the server is updatable, prompts galore, changes name.

.EXAMPLE
Repair-DbaServerName -SqlServer sql2014 -AutoFix

Even more prompts/confirms, but removes Replication or breaks mirroring if necessary.

.EXAMPLE   
Repair-DbaServerName -SqlServer sql2014 -AutoFix -Force
	
Skips some prompts/confirms but not all of them.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$AutoFix,
		[switch]$Force
	)
	
	BEGIN
	{
		if ($Force -eq $true) { $ConfirmPreference = "None" }
		$collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		$servercount++
		
		foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
			}
			catch
			{
				if ($servercount -eq 1 -and $SqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}
			
			if ($server.isClustered)
			{
				if ($servercount -eq 1 -and $SqlServer.count -eq 1)
				{
					# If we ever decide with a -Force to support a cluster name change
					# We would compare $server.NetName, and never ComputerNamePhysicalNetBIOS
					throw "$servername is a cluster. Microsoft does not support renaming clusters."
				}
				else
				{
					Write-Warning "$servername is a cluster. Microsoft does not support renaming clusters."
					Continue
				}
			}
			
			if ($server.VersionMajor -eq 8)
			{
				if ($servercount -eq 1 -and $SqlServer.count -eq 1)
				{
					throw "SQL Server 2000 not supported."
				}
				else
				{
					Write-Warning "SQL Server 2000 not supported. Skipping $servername."
					Continue
				}
			}
			
			# Check to see if we can easily proceed
			Write-Verbose "Executing Test-DbaServerName to see if the server is in a state to be renamed. "
			
			$nametest = Test-DbaServerName $servername -Detailed -NoWarning
			$serverinstancename = $nametest.ServerInstanceName
			$sqlservername = $nametest.SqlServerName
			
			if ($nametest.RenameRequired -eq $false)
			{
				return "Good news! $serverinstancename's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
			}
			
			if ($nametest.updatable -eq $false)
			{
				Write-Output "Test-DbaServerName reports that the rename cannot proceed with a rename in this $servername's current state."
				
				$nametest
				
				foreach ($nametesterror in $nametest.Blockers)
				{
					if ($nametesterror -like '*replication*')
					{
						$replication = $true
						
						if ($AutoFix -eq $false)
						{
							throw "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also break all database mirrors."
						}
						else
						{
							if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication."))
							{
								$title = "You have chosen to AutoFix the blocker: replication."
								$message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
								$result = $host.ui.PromptForChoice($title, $message, $options, 1)
								
								if ($result -eq 1)
								{
									throw "Cannot continue"
								}
								else
								{
									Write-Output "`nPerforming sp_dropdistributor @no_checks = 1"
									$sql = "sp_dropdistributor @no_checks = 1"
									Write-Debug $sql
									try
									{
										$null = $server.ConnectionContext.ExecuteNonQuery($sql)
										Write-Output "Successfully executed $sql`n"
									}
									catch
									{
										Write-Exception $_
										throw $_
									}
								}
							}
						}
					}
					elseif ($Error -like '*mirror*')
					{
						if ($AutoFix -eq $false)
						{
							throw "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also stop replication."
						}
						else
						{
							if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication."))
							{
								$title = "You have chosen to AutoFix the blocker: mirroring."
								$message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
								$result = $host.ui.PromptForChoice($title, $message, $options, 1)
								
								if ($result -eq 1)
								{
									Write-Output "Okay, moving on."
								}
								else
								{
									Write-Output "Removing Mirroring"
									
									foreach ($database in $server.Databases)
									{
										if ($database.IsMirroringEnabled)
										{
											$dbname = $database.name
											
											try
											{
												Write-Output "Breaking mirror for $dbname"
												$database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
												$database.Alter()
												$database.Refresh()
											}
											catch
											{
												Write-Exception $_
												throw "Could not break mirror for $dbname. Skipping."
											}
										}
									}
								}
							}
						}
					}
				}
			}
			# ^ That's embarassing
			
			$instancename = $instance = $server.InstanceName
			
			if ($instancename.length -eq 0)
			{
				$instancename = $instance = "MSSQLSERVER"
			}
			
			try
			{
				$allsqlservices = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instance*" -and $_.Status -eq "Running" }
			}
			catch
			{
				Write-Warning "Can't contact $servername using Get-Service. This means the script will not be able to automatically restart SQL services."
			}
			
			if ($nametest.Warnings.length -gt 0)
			{				
				$reportingservice = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -DisplayName "SQL Server Reporting Services ($instance)" -ErrorAction SilentlyContinue
				
				if ($reportingservice.Status -eq "Running")
				{
					if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?"))
					{
						$reportingservice | Stop-Service
						Write-Warning "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $sqlservername, then sp_addserver to add $serverinstancename"))
			{
				$sql = "sp_dropserver '$sqlservername'"
				Write-Debug $sql
				try
				{
					$null = $server.ConnectionContext.ExecuteNonQuery($sql)
					Write-Output "`nSuccessfully executed $sql"
				}
				catch
				{
					Write-Exception $_
					throw $_
				}
				
				$sql = "sp_addserver '$serverinstancename', local"
				Write-Debug $sql
				
				try
				{
					$null = $server.ConnectionContext.ExecuteNonQuery($sql)
					Write-Output "Successfully executed $sql"
				}
				catch
				{
					Write-Exception $_
					throw $_
				}
				$renamed = $true
			}
			
			if ($allsqlservices -eq $null)
			{
				Write-Warning "Could not contact $($server.ComputerNamePhysicalNetBIOS) using Get-Service. You must manually restart the SQL Server instance."
				$needsrestart = $true
			}
			else
			{
				if ($Pscmdlet.ShouldProcess($server.ComputerNamePhysicalNetBIOS, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instancname instance now?"))
				{
					try
					{
						Write-Output "`nStopping SQL Services for the $instancename instance"
						$allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
						Write-Output "Starting SQL Services for the $instancename instance"
						$allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
					}
					catch
					{
						Write-Exception $_
						throw "Could not restart at least one SQL Service :("
					}
				}
			}
			
			if ($renamed -eq $true)
			{
				Write-Output "`n$servername successfully renamed from $sqlservername to $serverinstancename"
			}
			
			if ($needsrestart -eq $true)
			{
				Write-Output "SQL Service restart for $serverinstancename still required"
			}
		}
	}
	END
	{
		# Nothing needed
	}
}