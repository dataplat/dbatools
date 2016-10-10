Function Set-DbaMaxDop
{
<# 
.SYNOPSIS 
Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings. Works on SQL Server 2005-2016.

.DESCRIPTION 
Uses the Test-DbaMaxDop command to get the recommended value if -MaxDop parameter is not specified.

These are just general recommendations for SQL Server and are a good starting point for setting the “max degree of parallelism” option.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER MaxDop
Allows you to specify the MaxDop value that you want to use.

.NOTES 
Author  : Cláudio Silva (@claudioessilva)
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Set-DbaMaxDop

.EXAMPLE   
Set-DbaMaxDop -SqlServer sql2008, sqlserver2012

Set recommended Max DOP setting for servers sql2008 and sqlserver2012.

.EXAMPLE 
Set-DbaMaxDop -SqlServer sql2014 -MaxDop 4

Set Max DOP setting to 4 for server sql2014.

.EXAMPLE 
Test-DbaMaxDop -SqlServer sql2008 | Set-DbaMaxDop 

Get Max DOP recommended setting from Test-DbaMaxDop and applies to sql2008 instance

.EXAMPLE 
Set-DbaMaxDop -SqlServer sql2016 -Databases db1

Set recommended Max DOP setting database db1 on server sql2016.
 

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [int]$MaxDop = -1,
        [Parameter(ValueFromPipeline = $True)]
		[object]$collection
	)
    
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
        $hasValues = $false

		$processed = New-Object System.Collections.ArrayList
        $results = @()
	}
	PROCESS
	{
        if ($MaxDop -eq -1)
        {
            $UseRecommended = $true
        }

        if ($collection -eq $null)
		{
			$collection = Test-DbaMaxDop -SqlServer $SqlServer
		}

        if ($databases -gt 0)
        {
            $collection = $collection | Where-Object {$_.Database -in $databases}
        }

        $collection | Add-Member -NotePropertyName OldInstanceMaxDopValue -NotePropertyValue 0
        $collection | Add-Member -NotePropertyName OldDatabaseMaxDopValue -NotePropertyValue 0

        $servers = $collection | Select-Object Instance -Unique

        foreach ($server in $servers)
		{
            $servername = $server.Instance

            $toprocess = $collection | Where-Object {$_.Instance -eq "$servername"}

            if ($servername -notin $processed)
			{
				$null = $processed.Add($servername)
			}
			else
			{
				continue
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

            $servername = $server.Name

            if (($databases.Count -gt 0) -or @($toprocess | Where-Object {$_.DatabaseMaxDop -ne "N/A"} | Select-Object DatabaseMaxDop -Unique).Count -gt 0)
            {
                if ($server.versionMajor -ge 13)
		        {
                    Write-Verbose "Server '$servername' supports Max DOP configuration per database."
                }
                else
                {
                    Write-Warning "Server '$servername' does not supports Max DOP configuration per database. Run the command again without -Databases parameter. Skipping."
                    Continue
                }

                if (@($toprocess | Where-Object {$_.DatabaseMaxDop -ne "N/A"} | Select-Object DatabaseMaxDop -Unique).Count -gt 0)
                {
                    $dbscopedconfiguration = $true
                }
                else
                {
                    $dbscopedconfiguration = $false
                }
            }

            #If CurrentMaxDop equal Recommended MaxDop and all Databases Maxdop are equal to 0 don't do nothing
            if ($dbscopedconfiguration -and  @($toprocess | Where-Object {$_.DatabaseMaxDop -ne "N/A"} | Select-Object DatabaseMaxDop -Unique).Count -eq 1)
            {
                if (($toprocess | Select-Object RecommendedMaxDop -Unique).RecommendedMaxDop -eq ($toprocess | Select-Object CurrentInstanceMaxDop -Unique).CurrentInstanceMaxDop `
                    -and ($toprocess | Where-Object {$_.DatabaseMaxDop -ne "N/A"} | Select-Object DatabaseMaxDop -Unique).DatabaseMaxDop -eq 0)
                {
                    Write-Host "Server '$servername' skipped. No changes needed."
                    continue
                }
            }
            else
            {
                if (($toprocess | Select-Object RecommendedMaxDop).RecommendedMaxDop -eq ($toprocess | Select-Object CurrentInstanceMaxDop).CurrentInstanceMaxDop)
                {
                    Write-Host "Server '$servername' skipped. No changes needed."
                    continue
                }
            }

            <#
                If set configuration on SQL2016 which have database scoped configurations, and if all databases have the same DOP, we will set the recommended at server level
                and keep all databases with 0 which means will use server configuration
            #>
            if (
                        @($toprocess | Where-Object {$_.DatabaseMaxDop -ne "N/A"} | Select-Object DatabaseMaxDop -Unique).Count -eq 1 `
                    -and (($toprocess | Select-Object DatabaseMaxDop -Unique -First 1).DatabaseMaxDop -eq ($toprocess | Select-Object RecommendedMaxDop -Unique -First 1).RecommendedMaxDop) `
                    -and $databases.Count -eq 0
                )
            {
                Write-Verbose "Databases have the same MAX DOP as the instance. Will set max DOP for databases to 0 which means that will use server configuration."
                foreach ($row in $toprocess)
		        {
                    $row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop
                    $row.DatabaseMaxDop = 0
                }

                $resetDatabases = $true
                $RecommendedMaxDop = ($toprocess | Select-Object RecommendedMaxDop -Unique -First 1).RecommendedMaxDop
            }
            else
            {
                $resetDatabases = $false
            }

            foreach ($row in $toprocess)
		    {
                
			    $row.OldInstanceMaxDopValue = $row.CurrentInstanceMaxDop

			    try
			    {
				    if ($UseRecommended)
				    {
                        if ($dbscopedconfiguration)
                        {
                            if ($resetDatabases)
                            {
                                Write-Verbose "Changing $($row.Database) database max DOP to $($row.DatabaseMaxDop)."
                                $server.Databases["$($row.Database)"].MaxDop = $row.DatabaseMaxDop
                            }
                            else
                            {
                                Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)"
                                $server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
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
                            Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $MaxDop"
					        $server.Databases["$($row.Database)"].MaxDop = $MaxDop
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
				
                    $hasValues = $true

                    $object = New-Object PSObject -Property @{
				                Instance = $row.Instance
                                InstanceVersion = $row.InstanceVersion
                                Database = $row.Database
                                DatabaseMaxDop = $row.DatabaseMaxDop
				                CurrentInstanceMaxDop = $row.CurrentInstanceMaxDop
				                RecommendedMaxDop = $row.RecommendedMaxDop
                                OldDatabaseMaxDopValue = $row.OldDatabaseMaxDopValue
                                OldInstanceMaxDopValue = $row.OldInstanceMaxDopValue
			                }
                    $results += $object
			    }
			    catch { Write-Error "Could not modify Max Degree of Paralellism for $server." }
		    }

            if ($resetDatabases)
            {
                Write-Verbose "Set server max dop to recommended."

                $server.Configuration.MaxDegreeOfParallelism.ConfigValue = $RecommendedMaxDop

                if ($Pscmdlet.ShouldProcess($servername, "Setting max dop on instance after changed all databases"))
                {
                    $server.Configuration.Alter()
                }          
            }
            $server.ConnectionContext.Disconnect()
        }
		
        if ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
        {
            if ($hasValues)
            {
            
                if ($dbscopedconfiguration)
                {
                    return $results | Select Instance, Database, OldDatabaseMaxDopValue, @{ name = "CurrentDatabaseMaxDopValue"; expression = { $_.DatabaseMaxDop } }, OldInstanceMaxDopValue, CurrentInstanceMaxDop
                    #return $collection | Select Instance, Database, OldDatabaseMaxDopValue, @{ name = "CurrentDatabaseMaxDopValue"; expression = { $_.DatabaseMaxDop } }, OldInstanceMaxDopValue, CurrentInstanceMaxDop
                }
                else
                {
                    return $results | Select Instance, OldInstanceMaxDopValue, CurrentMaxDopValue
		            #return $collection | Select Instance, OldInstanceMaxDopValue, CurrentMaxDopValue
                }
            }
            else
            {
                Write-Host "Nothing have changed."
            }
        }
	}
}