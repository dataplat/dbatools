function Get-DbaTable
{
<#
.SYNOPSIS
Returns a summary of information on the tables

.DESCRIPTION
Shows table information around table row and data sizes and if it has any table type information. 

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information

.PARAMETER Table
Define a specific table you would like to query

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages
	
.NOTES 
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
.LINK
https://dbatools.io/Get-DbaTable
	
.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Database Test1
Return all tables in the Test1 database
	
.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Database MyDB -Table MyTable
Return only information on the table MyTable from the database MyDB
	
.EXAMPLE
Get-DbaTable -SqlInstance DEV01 -Table MyTable
Returns information on table called MyTable if it exists in any database on the server, under any schema
	
.EXAMPLE
'localhost','localhost\namedinstance' | Get-DbaTable -Database DBA -Table Commandlog
Returns information on the CommandLog table in the DBA database on both instances localhost and the named instance localhost\namedinstance

#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$IncludeSystemDBs,
		[string[]]$Table,
		[switch]$Silent
	)
	
	begin
	{
       $fqtns = @()
		
		if ($Table)
		{
			foreach ($t in $Table)
			{
				$dotcount = ([regex]::Matches($t, "\.")).count
				
                $database = $NULL
                $Schema = $NULL

				if ($dotcount -eq 1)
				{
					$schema = $t.Split(".")[0]
					$tbl = $t.Split(".")[1]
				}
				
				if ($dotcount -eq 2)
				{
					$database = $t.Split(".")[0]
					$schema = $t.Split(".")[1]
					$tbl = $t.Split(".")[2]
				}
				
				$fqtn = [PSCustomObject] @{
					Database = $database
					Schema = $Schema
					Table = $tbl
				}
				$fqtns += $fqtn
			}
		}
        #$fqtns
	}
	
	process
	{
		foreach ($instance in $sqlinstance)
		{	
			try
			{
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance -InnerErrorRecord $_
			}
			
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
			try
			{
				if ($database)
				{
					$dbs = $server.Databases | Where-Object { $database -contains $_.Name -and $_.status -eq 'Normal' }
				}
				elseif ($IncludeSystemDBs)
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch
			{
				Stop-Function -Message "Unable to gather dbs for $instance" -Target $instance -Continue -InnerErrorRecord $_
			}
            
            foreach ($db in $dbs)
		    {
				Write-Message -Level Verbose -Message "Processing $db"
				
				$d = $server.Databases[$db]
				
				if ($fqtns.Count -gt 0)
				{
					foreach ($fqtn in $fqtns)
					{
                        if ($fqtn.schema -ne $NULL)
						{
							try
							{
								$tables = $db.Tables | Where-Object { $_.name -eq $tbl -and $_.Schema -eq $schema }
							}
							catch
							{
								Write-Message -Level Warning -Message "Could not find table name: $($fqtn.tbl) schema: $($fqtn.schema)" -ErrorRecord $_
							}
						}
						else
						{
							try
							{
								$tables = $db.Tables | Where-Object { $_.name -eq $tbl }
							}
							catch
							{
								Write-Message -Level Warning -Message "Could not find table name: $($fqtn.tbl)" -ErrorRecord $_
							}
						}
					}
				}
				else
				{
					$tables = $db.Tables
				}
				
				$tables | Add-Member -MemberType NoteProperty -Name ComputerName -Value $server.NetName
				$tables | Add-Member -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
				$tables | Add-Member -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
				
				$defaultprops = "ComputerName", "InstanceName", "SqlInstance","Parent as Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex", "IsFileTable", "IsMemoryOptimized", "IsPartitioned", "FullTextIndex", "ChangeTrackingEnabled"
				
				Select-DefaultView -InputObject $tables -Property $defaultprops
			}
		}
	}
}

