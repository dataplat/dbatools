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

        $collection | Add-Member -NotePropertyName OldInstanceMaxDopValue -NotePropertyValue 0
        $collection | Add-Member -NotePropertyName OldDatabaseMaxDopValue -NotePropertyValue 0

        foreach ($row in $collection)
		{
            $sqlserver = $row.Instance

			Write-Verbose "Attempting to connect to $sqlserver"
			try
			{
				$server = Connect-SqlServer -SqlServer $row.Instance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $sqlserver or access denied. Skipping."
				continue
			}
			
			if (!(Test-SqlSa -SqlServer $server))
			{
				Write-Error "Not a sysadmin on $sqlserver. Skipping."
				$server.ConnectionContext.Disconnect()
				continue
			}

            if (($databases.Count -gt 0) -or !([string]::IsNullOrEmpty($row.Database)))
            {
                if ($server.versionMajor -ge 13)
		        {
                    Write-Verbose "Server '$sqlserver' supports Max DOP configuration per database."
                }
                else
                {
                    Write-Warning "Server '$sqlserver' does not supports Max DOP configuration per database. Run the command again without -Databases parameter. Skipping."
                    Continue
                }
            }

			$row.OldInstanceMaxDopValue = $row.CurrentInstanceMaxDop
            $row.OldDatabaseMaxDopValue = $row.DatabaseMaxDop

            if ([string]::IsNullOrEmpty($row.Database))
            {
                $dbscopedconfiguration = $false
            }
            else
            {
                $dbscopedconfiguration = $true
            }
			
			try
			{
				if ($UseRecommended)
				{
                    if ($dbscopedconfiguration)
                    {
                        Write-Verbose "Changing $($row.Database) database max DOP from $($row.DatabaseMaxDop) to $($row.RecommendedMaxDop)"
					    $server.Databases["$($row.Database)"].MaxDop = $row.RecommendedMaxDop
                    }
                    else
                    {
					    Write-Verbose "Changing $sqlserver SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $($row.RecommendedMaxDop)"
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
					    Write-Verbose "Changing $sqlserver SQL Server max DOP from $($row.CurrentInstanceMaxDop) to $MaxDop"
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
                    if ($Pscmdlet.ShouldProcess($server, "Setting max dop on instance"))
                    {
                        $server.Configuration.Alter()
                    }
                }
				
                $hasValues = $true
			}
			catch { Write-Error "Could not modify Max Degree of Paralellism for $sqlserver." }
			
			$server.ConnectionContext.Disconnect()
		}
		
        if ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
        {
            if ($hasValues)
            {
            
                if ($dbscopedconfiguration)
                {
                    return $collection | Select Instance, Database, OldDatabaseMaxDopValue, @{ name = "DatabaseMaxDop"; expression = { $_.CurrentInstanceMaxDop } }, OldInstanceMaxDopValue, @{ name = "CurrentMaxDopValue"; expression = { $_.CurrentInstanceMaxDop } }
                }
                else
                {
		            return $collection | Select Instance, OldInstanceMaxDopValue, @{ name = "CurrentMaxDopValue"; expression = { $_.CurrentInstanceMaxDop } }
                }
            }
        }
	}
}