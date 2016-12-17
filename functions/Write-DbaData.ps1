Function Write-DbaData
{
<#
.SYNOPSIS
Writes data to a table

.DESCRIPTION
Description

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

	
.NOTES
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Write-DbaData

.EXAMPLE
Write-DbaData -SqlServer sql2014

Creates an SMO Server object that connects using Windows Authentication
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[Alias("Credential")]
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Parameter(ValueFromPipeline = $true)]
		[object]$Data,
		[string]$Schema = 'dbo',
		[Parameter(Mandatory = $true)]
		[string]$Table,
		[int]$BatchSize = 50000,
		[int]$NotifyAfter,
		[switch]$TableLock, # change to $NoTableLock?
		[switch]$CheckConstraints,
		[switch]$FireTriggers,
		[switch]$KeepIdentity,
		[switch]$KeepNulls,
		[switch]$Trucnate
		#,[switch]$CreateTable
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabase -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
PROCESS {
	<#
		function New-SqlTable # Can be improved but i'm bizzy, mmm actually, will implement later
		{
			$Data.Tables.Rows[0]
			
			# Get SQL datatypes by best guess on first data row
			$sqldatatypes = @(); $index = -1
			
			foreach ($column in $columntext)
			{
				$sqlcolumnname = $columns[$index++]
				
				# bigint, float, and datetime are more accurate, but it didn't work
				# as often as it should have, so we'll just go for a smaller datatype
				
				if ([int64]::TryParse($column, [ref]0) -eq $true)
				{
					$sqldatatype = "varchar(255)"
				}
				elseif ([double]::TryParse($column, [ref]0) -eq $true)
				{
					$sqldatatype = "varchar(255)"
				}
				elseif ([datetime]::TryParse($column, [ref]0) -eq $true)
				{
					$sqldatatype = "varchar(255)"
				}
				else
				{
					$sqldatatype = "varchar(MAX)"
				}
				
				$sqldatatypes += "$sqlcolumnname $sqldatatype"
			}
			
			$sql = "BEGIN CREATE TABLE [$table] ($($sqldatatypes -join ' NULL,')) END"
			
			Write-Verbose $sql
			
			try
			{
				$null = $server.Databases[$database].ExecuteNonQuery($sql)
			}
			catch
			{
				$errormessage = $_.Exception.Message.ToString()
			}
		}
	#>
	
	$fqtn = "$Schema.$table"
	
	$database = $psboundparameters.Database
	$validtypes = @([System.Data.Common.DbDataReader], [System.Data.DataTable], [System.Data.DataRow[]], [System.Data.IDataReader])
	
	if ($data.GetType() -notin $validtypes)
	{
		Write-Warning "Data is not of the right type (DbDataReader, DataTable, DataRow, or IDataReader)."
		continue
	}
	
	$server = Connect-SqlServer-SqlServer $SqlServer -SqlCredential $SqlCredential
	
	if ($database.length -gt 0) { $server.ConnectionContext.DatabaseName = $Database }
	
	$tableExists = $server.Databases[$Database] | Where-Object { $_.Tables.Name -eq 'allcountries' -and $_.Tables.Schema -eq 'dbo' }
	
	if ($tableExists -eq $null)
	{
		Write-Warning "$database.$fqtn does not exist"
		continue
	}
	
	$bulkCopyOptions = @()
	$options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default", "Truncate"
	
	foreach ($option in $options)
	{
		$optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
		if ($optionValue -eq $true) { $bulkCopyOptions += "$option" }
	}
	
	$bulkCopyOptions = $bulkCopyOptions -join " & "
	
	if ($truncate -eq $true)
	{
		try
		{
			$null = $server.Databases[$database].ExecuteNonQuery("TRUNCATE TABLE [$table]")
		}
		catch
		{
			Write-Warning "Could not truncate $table"
		}
	}
	
	$bulkcopy = New-Object Data.SqlClient.SqlBulkCopy($server, $bulkCopyOptions)
	$bulkcopy.DestinationTableName = $fqtn
	$bulkcopy.BatchSize = $batchsize
	$bulkcopy.WriteToServer($data)
	$bulkcopy.Close()
	$bulkcopy.Dispose()
} 