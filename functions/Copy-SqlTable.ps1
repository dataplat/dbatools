Function Export-SqlTable
{
<# 
.SYNOPSIS
Efficiently imports very large (and small) CSV files into SQL Server using only the .NET Framework and PowerShell.

.DESCRIPTION
Import-CsvToSql takes advantage of .NET's super fast SqlBulkCopy class to import CSV files into SQL Server at up to 90,000
rows a second.
	
The entire import is contained within a transaction, so if a failure occurs or the script is aborted, no changes will persist.

If the table specified does not exist, it will be automatically created using best guessed data types. In addition, 
the destination table can be truncated prior to import. 

The Query parameter be used to import only data returned from a SQL Query executed against the CSV file(s). This function 
supports a number of bulk copy options. Please see parameter list for details.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER CSV
Required. The location of the CSV file(s) to be imported. Multiple files are allowed, so long as they are formatted 
similarly. If no CSV file is specified, a Dialog box will appear.

.PARAMETER FirstRowColumns
Optional. This parameter specifies whether the first row contains column names. If the first row does not contain column 
names and -Query is specified, use field names "column1, column2, column3" and so on.

.PARAMETER Delimiter
Optional. If you do not pass a Delimiter, then a comma will be used. Valid Delimiters include: tab "`t", pipe "|", 
semicolon ";", and space " ".

.PARAMETER SqlServer
Required. The destination SQL Server.

.PARAMETER SqlCredential
Connect to SQL Server using specified SQL Login credentials.

.PARAMETER Database
Required. The name of the database where the CSV will be imported into. This parameter is autopopulated using the 
-SqlServer and -SqlCredential (optional) parameters. 

.PARAMETER Table
SQL table or view where CSV will be imported into. 

If a table name is not specified, the table name will be automatically determined from filename, and a prompt will appear
to confirm table name.

If table does not currently exist, it will created.  SQL datatypes are determined from the first row of the CSV that 
contains data (skips first row if -FirstRowColumns). Datatypes used are: bigint, numeric, datetime and varchar(MAX). 

If the automatically generated table datatypes do not work for you, please create the table prior to import.

.PARAMETER Query
Optional. Cannot be used in conjunction with -Turbo or -First. When Query is specified, the slower import method, OleDb,
will be used.

If you want to import just the results of a specific query from your CSV file, use this parameter.
To make command line queries easy, this module will convert the word "csv" to the actual CSV formatted table name. 
If the FirstRowColumns switch is not used, the query should use column1, column2, column3, etc

Example: select column1, column2, column3 from csv where column2 > 5
Example: select distinct artist from csv
Example: select top 100 artist, album from csv where category = 'Folk'

See EXAMPLES for more example syntax.

.PARAMETER SqlCredentialPath
Internal parameter.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net


.EXAMPLE   
Import-CsvToSql -Csv C:\temp\housing.csv -SqlServer sql001 -Database markets

Imports the entire *comma delimited* housing.csv to the SQL "markets" database on a SQL Server named sql001.
Since a table name was not specified, the table name is automatically determined from filename as "housing"
and a prompt will appear to confirm table name.

The first row is not skipped, as it does not contain column names.

#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		#[Parameter(Mandatory=$true)]
		[string]$SqlServer,
		[object]$SqlCredential,
		[string]$Delimiter = ",",
		[string]$testdb = $PSBoundParameters.SqlServer,
		[switch]$FirstRowColumns #,
		#[parameter(ParameterSetName="query")]
		#[Parameter(Mandatory=$true)]
		#[string]$Query = "select * from csv"
	)
	
	DynamicParam
	{
		#foreach ($Item in $PSBoundParameters) {$items += $item }
		#add-content -Path $items
		$PSBoundParameters | export-clixml C:\temp\boundparams.txt
		
		if ($PSBoundParameters.SqlServer.Count -eq 1)
		{
			# Reusable parameter setup
			$global:newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
			$attributes = New-Object System.Management.Automation.ParameterAttribute
			$attributes.Mandatory = $false
			
			if ($SqlCredentialPath.length -gt 0)
			{
				$SqlCredential = Import-CliXml $SqlCredentialPath
			}
			
			# Auto populate database list from specified sqlserver
			$paramconn = New-Object System.Data.SqlClient.SqlConnection
			if ($SqlCredential.count -eq 0 -or $SqlCredential -eq $null)
			{
				$paramconn.ConnectionString = "Data Source=$sqlserver;Integrated Security=True;Connect Timeout=2"
			}
			else
			{
				$paramconn.ConnectionString = "Data Source=$sqlserver;User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password);Connect Timeout=2"
			}
			$paramconn.Open()
			
			if ($PSBoundParameters.Database.Count -eq 0)
			{
				write-warning "no db"
				try
				{
					$sql = "select name from master.dbo.sysdatabases"
					$paramcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $paramconn, $null)
					$paramdt = New-Object System.Data.DataTable
					$paramdt.Load($paramcmd.ExecuteReader())
					$databaselist = $paramdt.rows.name
				}
				catch
				{
					# But if the routine fails, at least let them specify a database manually
					$databaselist = ""
				}
				
				# Database list parameter setup
				$dbattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
				$dbattributes.Add($attributes)
				# If a list of databases were returned, populate the parameter set
				if ($databaselist.length -gt 0)
				{
					$dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $databaselist
					$dbattributes.Add($dbvalidationset)
				}
				
				$Database = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Database", [String], $dbattributes)
				$newparams.Add("Database", $Database)
				write-warning  $newparams.Count
			}
			try
			{
				$sql = "select name from $($PSBoundParameters.Database).sys.tables order by name"
				write-warning $sql
				$paramcmd = New-Object System.Data.SqlClient.SqlCommand($sql, $paramconn, $null)
				$paramdt = New-Object System.Data.DataTable
				$paramdt.Load($paramcmd.ExecuteReader())
				$tablelist = $paramdt.rows.name
				$null = $paramcmd.Dispose()
				$null = $paramconn.Close()
				$null = $paramconn.Dispose()
			}
			catch
			{
				$error[0]
				# But if the routine fails, at least let them specify a database manually
				$tablelist = ""
			}
			
			# Reusable parameter setup
			$attributes = New-Object System.Management.Automation.ParameterAttribute
			$attributes.Mandatory = $false
			
			# Database list parameter setup
			$tbattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$tbattributes.Add($attributes)
			# If a list of databases were returned, populate the parameter set
			if ($tablelist.length -gt 0)
			{
				$tbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $tablelist
				$tbattributes.Add($tbvalidationset)
			}
			
			$Table = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Table", [String], $tbattributes)
			$newparams.Add("Table", $Table)
			return $newparams
		}
	}
	
	Begin
	{
		
		Function Test-SqlConnection
		{
	<#
		.SYNOPSIS
		Uses System.Data.SqlClient to gather list of user databases.

		.EXAMPLE
		$SqlCredential = Get-Credential
		Get-SqlDatabases -SqlServer sqlservera -SqlCredential $SqlCredential
		
		.OUTPUT
		Array of user databases
				
	 #>
			param (
				[Parameter(Mandatory = $true)]
				[string]$SqlServer,
				[object]$SqlCredential
			)
			$testconn = New-Object System.Data.SqlClient.SqlConnection
			if ($SqlCredential.count -eq 0)
			{
				$testconn.ConnectionString = "Data Source=$sqlserver;Integrated Security=True;Connection Timeout=3"
			}
			else
			{
				$testconn.ConnectionString = "Data Source=$sqlserver;User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password);Connection Timeout=3"
			}
			try
			{
				$testconn.Open()
				$testconn.Close()
				$testconn.Dispose()
				return $true
			}
			catch
			{
				$message = $_.Exception.Message.ToString()
				Write-Verbose $message
				if ($message -match "A network") { $message = "Can't connect to $sqlserver." }
				elseif ($message -match "Login failed for user") { $message = "Login failed for $username." }
				return $message
			}
		}
	}
	
	Process
	{
		#write-warning $PSBoundParameters.SqlServer.Count
		#write-warning $PSBoundParameters.Database.Count
		#write-warning $PSBoundParameters.Table
	}
	
	End
	{
		# Close everything just in case & ignore errors
		try { $null = $sqlconn.close(); $null = $sqlconn.Dispose(); }
		catch { }
		
	}
}