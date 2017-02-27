Function Set-DbaMaxDop
{
<# 
.SYNOPSIS 
Sets SQL Server max dop then displays information relating to SQL Server Max DOP configuration settings. Works on SQL Server 2005-2016.

.DESCRIPTION 
Uses the Test-DbaMaxDop command to get the recommended value if -MaxDop parameter is not specified.

These are just general recommendations for SQL Server and are a good starting point for setting the "max degree of parallelism" option.
You can set MaxDop database scoped configurations if the server is version 2016.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER MaxDop
Allows you to specify the MaxDop value that you want to use.

.PARAMETER AllDatabases
This is a parameter that was included so you can set MaxDop value to all databases. Only valid when using on SQL Server 2016 instances.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Collection
Results of Test-SQLMaxDop to be passed into the command

.NOTES 
Author  : Claudio Silva (@claudioessilva)
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Set-DbaMaxDop

.EXAMPLE   
Set-DbaMaxDop -SqlServer sql2008, sql2012

Set recommended Max DOP setting for servers sql2008 and sql2012.

.EXAMPLE 
Set-DbaMaxDop -SqlServer sql2014 -MaxDop 4

Set Max DOP setting to 4 for server sql2014.

.EXAMPLE 
Test-DbaMaxDop -SqlServer sql2008 | Set-DbaMaxDop 

Get Max DOP recommended setting from Test-DbaMaxDop and applies to sql2008 instance

.EXAMPLE 
Set-DbaMaxDop -SqlServer sql2016 -Databases db1

Set recommended Max DOP setting database db1 on server sql2016.

.EXAMPLE 
Set-DbaMaxDop -SqlServer sql2016 -AllDatabases

Set recommended Max DOP setting for all databases on server sql2016.
 

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[int]$MaxDop = -1,
		[Parameter(ValueFromPipeline = $True)]
		[object]$Collection,
        [Alias("All")]
        [switch]$AllDatabases
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases

        if ($databases -gt 0 -and $AllDatabases)
        {
            throw "-Databases and -AllDatabases are mutually exclusive. Please choose only one. Quitting"
        }
		
		$processed = New-Object System.Collections.ArrayList
        $results = @()
	}
	PROCESS
	{
        $dbscopedconfiguration = $false

		if ($MaxDop -eq -1)
		{
			$UseRecommended = $true
		}
		
		if ($collection -eq $null)
		{
			$collection = Test-DbaMaxDop -SqlServer $SqlServer -SqlCredential $SqlCredential -Verbose:$false
		}
		elseif ($collection.Instance -eq $null)
		{
			$collection = Test-DbaMaxDop -SqlServer $SqlServer -SqlCredential $SqlCredential -Verbose:$false
		}
		
		$collection | Add-Member -NotePropertyName OldInstanceMaxDopValue -NotePropertyValue 0
		$collection | Add-Member -NotePropertyName OldDatabaseMaxDopValue -NotePropertyValue 0
		
		$servers = $collection | Select-Object Instance -Unique
		
		foreach ($server in $servers)
		{
			if ($server.Instance -ne $null)
			{
				$servername = $server.Instance
			}
			else
			{
				$servername = $server
			}
			
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $server or access denied. Skipping."
				continue
			}
			
			if (!(Test-SqlSa -SqlServer $server))
			{
				Write-Error "Not a sysadmin on $server. Skipping."
				$server.ConnectionContext.Disconnect()
				continue
			}

            if ($server.versionMajor -ge 13)
		    {
                
			    Write-Verbose "Server '$servername' supports Max DOP configuration per database."

                if ($databases -eq 0)
                {
                    #Set at instance level
                    $collection = $collection | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                }
                else
                {
                    $dbscopedconfiguration = $true

                    if (!$AllDatabases -and $databases -gt 0)
                    {
                        
                        $collection = $collection | Where-Object { $_.Database -in $databases }
                    }
                    else
                    {
                        if ($AllDatabases)
                        {
                            $collection = $collection | Where-Object { $_.DatabaseMaxDop -ne "N/A" }
                        }
                        else
                        {
                            $collection = $collection | Where-Object { $_.DatabaseMaxDop -eq "N/A" }
                            $dbscopedconfiguration = $false
                        }
                    }
                }
            }
            else
            {
                if ($databases -gt 0 -or $AllDatabases)
                {
                    Write-Warning "Server '$servername' (v$($server.versionMajor)) does not support Max DOP configuration at the database level. Remember that this option is only available from SQL Server 2016 (v13). Run the command again without using database related parameters. Skipping."
				    Continue
			    }
            }

			foreach ($row in $collection | Where-Object { $_.Instance -eq $servername })
			{
				if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.CurrentInstanceMaxDop) -and !($dbscopedconfiguration))
                {
                    Write-Output "$servername is configured properly :) No change required."
                    Continue
                }

                if ($UseRecommended -and ($row.RecommendedMaxDop -eq $row.DatabaseMaxDop) -and $dbscopedconfiguration)
                {
                    Write-Output "Database $($row.Database) on $servername is configured properly :) No change required."
                    Continue
                }

				$row.OldInstanceMaxDopValue = $row.CurrentInstanceMaxDop
				
				try
				{
					if ($UseRecommended)
					{
						if ($dbscopedconfiguration)
						{
							$row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop
							
							if ($resetDatabases)
							{
								Write-Verbose "Changing $($row.Database) database max DOP to $($row.DatabaseMaxDop)."
								$server.Databases["$($row.Database)"].MaxDop = $row.DatabaseMaxDop
							}
							else
							{
								Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)"
								$server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
								$row.DatabaseMaxDop = $row.RecommendedMaxDop
							}
							
						}
						else
						{
							Write-Verbose "Changing $server SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $($row.RecommendedMaxDop)"
							$server.Configuration.MaxDegreeOfParallelism.ConfigValue = $row.RecommendedMaxDop
							$row.CurrentInstanceMaxDop = $row.RecommendedMaxDop
						}
					}
					else
					{
						if ($dbscopedconfiguration)
						{
                            $row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop

							Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $MaxDop"
							$server.Databases["$($row.Database)"].MaxDop = $MaxDop
							$row.DatabaseMaxDop = $MaxDop
						}
						else
						{
							Write-Verbose "Changing $servername SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $MaxDop"
							$server.Configuration.MaxDegreeOfParallelism.ConfigValue = $MaxDop
							$row.CurrentInstanceMaxDop = $MaxDop
						}
					}
					
					if ($dbscopedconfiguration)
					{
						if ($Pscmdlet.ShouldProcess($row.Database, "Setting max dop on database"))
						{
							$server.Databases["$($row.Database)"].Alter()
						}
					}
					else
					{
						if ($Pscmdlet.ShouldProcess($servername, "Setting max dop on instance"))
						{
							$server.Configuration.Alter()
						}
					}

					$results += [pscustomobject]@{
						Instance = $row.Instance
						InstanceVersion = $row.InstanceVersion
						Database = $row.Database
						DatabaseMaxDop = $row.DatabaseMaxDop
						CurrentInstanceMaxDop = $row.CurrentInstanceMaxDop
						RecommendedMaxDop = $row.RecommendedMaxDop
						OldDatabaseMaxDopValue = $row.OldDatabaseMaxDopValue
						OldInstanceMaxDopValue = $row.OldInstanceMaxDopValue
					}
				}
				catch { Write-Error "Could not modify Max Degree of Paralellism for $server." }
			}

			$server.ConnectionContext.Disconnect()
		}

	}
    END
    {
		
		if ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		{
			if ($dbscopedconfiguration)
			{
				return $results | Select-Object Instance, Database, OldDatabaseMaxDopValue, @{ name = "CurrentDatabaseMaxDopValue"; expression = { $_.DatabaseMaxDop } }
			}
			else
			{
				return $results | Select-Object Instance, OldInstanceMaxDopValue, CurrentInstanceMaxDop
			}
		}
    }
}
