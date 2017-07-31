function Write-DbaDataTable {
	<#
		.SYNOPSIS
			Writes data to a SQL Server Table

		.DESCRIPTION
			Writes a .NET DataTable to a SQL Server table using SQL Bulk Copy

		.PARAMETER SqlInstance
			The SQL Server instance.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

		.PARAMETER InputObject
			This is the DataTable (or datarow) to import to SQL Server.

		.PARAMETER Table
			The table name. You can specify a one, two, or three part table name. If you specify a one or two part name, you must also use -Database.

			If the table does not exist, you can use AutoCreateTable to automatically create the table with inefficient data types.

		.PARAMETER Schema
			Defaults to dbo if no schema is specified.

		.PARAMETER BatchSize
			The BatchSize for the import defaults to 5000.

		.PARAMETER NotifyAfter
			Sets the option to show the notification after so many rows of import

		.PARAMETER AutoCreateTable
			Automatically create the table if it doesn't exist. Note that the table will be created with inefficient data types such as nvarchar(max).

		.PARAMETER NoTableLock
			By default, a TableLock is placed on the destination table. Use this parameter to remove the lock.

		.PARAMETER CheckConstraints
			SqlBulkCopy option. Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

		.PARAMETER FireTriggers
			SqlBulkCopy option. Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the Database."

		.PARAMETER KeepIdentity
			SqlBulkCopy option. Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

		.PARAMETER KeepNulls
			SqlBulkCopy option. Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

		.PARAMETER Truncate
			Prompts for confirmation then truncates destination

		.PARAMETER BulkCopyTimeOut
			Value in seconds for the BulkCopy operations timeout, default is 30 seconds

		.PARAMETER RegularUser
			The underlying connection assumes the user connecting has administrative privilege, this switch removest that assumption
			This is particularly import and when connecting to a SQL Azure Database

		.PARAMETER Confirm
			Can disable prompt for confirmation by using -Confirm:$false

		.PARAMETER WhatIf
			Shows what would happen if the command were executed

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Write-DbaDataTable

		.EXAMPLE
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			Write-DbaDataTable -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers

			Quickly and efficiently performs a bulk insert of all the data in customers.csv into Database: mydb, schema: dbo, table: customers
			Shows progress as rows are inserted. If table does not exist, import is halted.

		.EXAMPLE
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			$DataTable | Write-DbaDataTable -SqlInstance sql2014 -Table mydb.dbo.customers

			Performs row by row insert. Super slow. No progress bar. Don't do this. Use -InputObject instead.

		.EXAMPLE
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			Write-DbaDataTable -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -AutoCreateTable

			Quickly and efficiently performs a bulk insert of all the data. If mydb.dbo.customers does not exist, it will be created with inefficient but forgiving DataTypes.

		.EXAMPLE
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			Write-DbaDataTable -SqlInstance sql2014 -InputObject $DataTable -Table mydb.dbo.customers -Truncate

			Quickly and efficiently performs a bulk insert of all the data. Prompts to confirm that truncating mydb.dbo.customers prior to import is desired.
			Prompts again to perform the import. Answer A for Yes to All.

		.EXAMPLE
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			Write-DbaDataTable -SqlInstance sql2014 -InputObject $DataTable -Database mydb -Table customers -KeepNulls

			Quickly and efficiently performs a bulk insert of all the data into mydb.dbo.customers -- since Schema was not specified, dbo was used.

			Per Microsoft, KeepNulls will "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

		.EXAMPLE
			$passwd = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
			$AzureCredential = Mew-Object System.Management.Automation.PSCredential("AzureAccount"),$passwd)
			$DataTable = Import-Csv C:\temp\customers.csv | Out-DbaDataTable
			Write-DbaDataTable -SqlInstance AzureDB.database.windows.net -InputObject $DataTable -Database mydb -Table customers -KeepNulls -Credential $AzureCredential -ReqularUser -BulkCopyTimeOut 300

			This performs the same operation as the previous example, but against a SQL Azure Database instance using the required credentials. The RegularUser switch is needed to prevent trying to get administrative privilege, and we increase the BulkCopyTimeout value to cope with any latency

		.EXAMPLE
			$process = Get-Process | Out-DbaDataTable
			Write-DbaDataTable -InputObject $process -SqlInstance sql2014 -Database mydb -Table myprocesses -AutoCreateTable

			Creates a table based on the Process object with over 60 columns, converted from PowerShell data types to SQL Server data types. After the table is created a bulk insert is performed to add process information into the table.

			This is a good example of the type conversion in action. All process properties are converted, including special types like TimeSpan. Script properties are resolved before the type conversion starts thanks to Out-DbaDataTable.
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[ValidateNotNull()]
		[DbaInstanceParameter]$SqlInstance,
		[Parameter(Position = 1)]
		[ValidateNotNull()]
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Parameter(Position = 2)]
		[object]$Database,
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("DataTable")]
		[ValidateNotNull()]
		[object]$InputObject,
		[Parameter(Position = 3, Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Table,
		[Parameter(Position = 4)]
		[ValidateNotNullOrEmpty()]
		[string]$Schema = 'dbo',
		[ValidateNotNull()]
		[int]$BatchSize = 50000,
		[ValidateNotNull()]
		[int]$NotifyAfter = 5000,
		[switch]$AutoCreateTable,
		[switch]$NoTableLock,
		[switch]$CheckConstraints,
		[switch]$FireTriggers,
		[switch]$KeepIdentity,
		[switch]$KeepNulls,
		[switch]$Truncate,
		[ValidateNotNull()]
		[int]$BulkCopyTimeOut = 5000,
		[switch]$RegularUser,
		[switch]$Silent
	)

	begin {
		if (!$Truncate) { $ConfirmPreference = "None" }

		# Getting the total rows copied is a challenge. Use SqlBulkCopyExtension.
		# http://stackoverflow.com/questions/1188384/sqlbulkcopy-row-count-when-complete

		$source = 'namespace System.Data.SqlClient
		{
			using Reflection;

			public static class SqlBulkCopyExtension
			{
				const String _rowsCopiedFieldName = "_rowsCopied";
				static FieldInfo _rowsCopiedField = null;

				public static int RowsCopiedCount(this SqlBulkCopy bulkCopy)
				{
					if (_rowsCopiedField == null) _rowsCopiedField = typeof(SqlBulkCopy).GetField(_rowsCopiedFieldName, BindingFlags.NonPublic | BindingFlags.GetField | BindingFlags.Instance);
					return (int)_rowsCopiedField.GetValue(bulkCopy);
				}
			}
		}'

		Add-Type -ReferencedAssemblies 'System.Data.dll' -TypeDefinition $source -ErrorAction SilentlyContinue

		$dotcount = ([regex]::Matches($table, "\.")).count

		if ($dotcount -lt 2 -and $Database -eq $null) {
			Stop-Function -Message "You must specify a database or fully qualififed table name"
			return
		}

		if ($dotcount -eq 1) {
			$schema = $Table.Split(".")[0]
			$table = $Table.Split(".")[1]
		}

		if ($dotcount -eq 2) {
			$Database = $Table.Split(".")[0]
			$schema = $Table.Split(".")[1]
			$table = $Table.Split(".")[2]
		}

		if ($Database -match "\[.*\]"){
			$Database = ($Database -replace '\[','') -replace '\]',''
		}

		if ($Schema -match "\[.*\]"){
			$Schema = ($Schema -replace '\[','') -replace '\]',''
		}

		if ($table -match "\[.*\]"){
			$table = ($table -replace '\[','') -replace '\]',''
		}

		$fqtn = "[$Database].[$Schema].[$table]"

		try {
			Write-Message -Level VeryVerbose -Message "Connecting to $SqlInstance" -Target $SqlInstance
			$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -RegularUser:$RegularUser
		}
		catch {
			Stop-Function -Message "Failed to process Instance $SqlInstance" -ErrorRecord $_ -Target $SqlInstance
			return
		}

		if ($server.servertype -eq 'SqlAzureDatabase') {
			#For some reasons SMO wants an initial pull when talking to Azure Sql DB
			#This will throw and be caught, and then we can continue as normal.
			try {
				$server.databases | out-null
			}
			catch {}
		}
		$db = $server.Databases | Where-Object Name -eq $Database

		if ($db -eq $null) {
			Stop-Function -Message "$Database does not exist" -Target $SqlInstance
			return
		}

		$bulkCopyOptions = @()
		$options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default", "Truncate"

		foreach ($option in $options) {
			$optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
			if ($optionValue -eq $true) { $bulkCopyOptions += "$option" }
		}

		$bulkCopyOptions = $bulkCopyOptions -join " & "

		if ($truncate -eq $true) {
			if ($Pscmdlet.ShouldProcess($SqlInstance, "Truncating $fqtn")) {
				try {
					Write-Message -Level Output -Message "Truncating $fqtn"
					$null = $server.Databases[$Database].ExecuteNonQuery("TRUNCATE TABLE $fqtn")
				}
				catch {
					Write-Message -Level Warning -Message "Could not truncate $fqtn. Table may not exist or may have key constraints." -ErrorRecord $_
				}
			}
		}

		$tablelock = $NoTableLock -eq $false

		$bulkcopy = New-Object Data.SqlClient.SqlBulkCopy("$($server.ConnectionContext.ConnectionString);Database=$Database")
		$bulkcopy.DestinationTableName = $fqtn
		$bulkcopy.BatchSize = $batchsize
		$bulkcopy.NotifyAfter = $NotifyAfter
		$bulkcopy.BulkCopyTimeOut = $BulkCopyTimeOut

		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		# Add rowcount output
		$bulkCopy.Add_SqlRowscopied( {
				$script:totalrows = $args[1].RowsCopied
				$percent = [int](($script:totalrows / $rowcount) * 100)
				$timetaken = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
				Write-Progress -id 1 -activity "Inserting $rowcount rows" -percentcomplete $percent -status ([System.String]::Format("Progress: {0} rows ({1}%) in {2} seconds", $script:totalrows, $percent, $timetaken))
			})

		$PStoSQLtypes = @{
			#PS datatype      = SQL data type
			'System.Int32'    = 'int';
			'System.UInt32'   = 'bigint';
			'System.Int16'    = 'smallint';
			'System.UInt16'   = 'int';
			'System.Int64'    = 'bigint';
			'System.UInt64' = 'decimal(20,0)';
			'System.Decimal'  = 'decimal(20,5)';
			'System.Single'   = 'bigint';
			'System.Double'   = 'float';
			'System.Byte'     = 'tinyint';
			'System.SByte'    = 'smallint';
			'System.TimeSpan' = 'nvarchar(30)';
			'System.String' = 'nvarchar(MAX)';
			'System.Char' = 'nvarchar(1)'
			'System.DateTime' = 'datetime2';
			'System.Boolean' = 'bit';
			'System.Guid' = 'uniqueidentifier';
			'Int32' = 'int';
			'UInt32' = 'bigint';
			'Int16' = 'smallint';
			'UInt16' = 'int';
			'Int64' = 'bigint';
			'UInt64' = 'decimal(20,0)';
			'Decimal'         = 'decimal(20,5)';
			'Single'          = 'bigint';
			'Double' = 'float';
			'Byte'            = 'tinyint';
			'SByte'           = 'smallint';
			'TimeSpan'        = 'nvarchar(30)';
			'String' = 'nvarchar(MAX)';
			'Char' = 'nvarchar(1)'
			'DateTime' = 'datetime2';
			'Boolean' = 'bit';
			'Bool' = 'bit';
			'Guid' = 'uniqueidentifier';
			'int' = 'int';
			'long' = 'bigint';
		}

	}
	process {
		if (Test-FunctionInterrupt) { return }
		if ($InputObject -eq $null) {
			Stop-Function -Message "Input object is null"
			return
		}

		$validtypes = @([System.Data.DataSet], [System.Data.DataTable], [System.Data.DataRow], [System.Data.DataRow[]]) #[System.Data.Common.DbDataReader], [System.Data.IDataReader]

			if ($InputObject.GetType() -notin $validtypes) {
			Stop-Function -Message "Data is not of the right type (DbDataReader, DataTable, DataRow, or IDataReader). Tip: Try using Out-DbaDataTable to convert the object first."
			return
		}

		If ($InputObject.GetType() -eq [System.Data.DataSet]) {
			if ($InputObject.Tables -ne $null) { $InputObject = $InputObject.Tables }
		}

		$db.tables.refresh()
		$tableExists = $db | Where-Object { $table -in $_.Tables.Name -and $_.Tables.Schema -eq $schema }

		if ($tableExists -eq $null) {
			if ($AutoCreateTable -eq $false) {
				Stop-Function -Message "$fqtn does not exist. Use -AutoCreateTable to AutoCreate."
				return
			}
			else {
				if ($schema -notin $server.Databases[0].Schemas.Name) {
					Stop-Function -Message "Schema does not exist"
					return
				}

				# Get SQL datatypes by best guess on first data row
				$sqldatatypes = @(); $index = -1
				$columns = $InputObject.Columns

				if ($columns -eq $null) { $columns = $InputObject.Table.Columns }

				foreach ($column in $columns) {
					$sqlcolumnname = $column.ColumnName

					try {
						$columnvalue = $InputObject.Rows[0].$sqlcolumnname
					}
					catch {
						$columnvalue = $InputObject.$sqlcolumnname
					}

					if ($columnvalue -eq $null) {
						$columnvalue = $InputObject.$sqlcolumnname
					}

					# PS to SQL type conversion
					# If data type exists in hash table, use the corresponding SQL type
					# Else, fallback to nvarchar
						if ($PStoSQLtypes.Keys -contains $column.DataType) {
						$sqldatatype = $PStoSQLtypes[$($column.DataType.toString())]
					}
					else {
						$sqldatatype = "nvarchar(MAX)"
					}

					$sqldatatypes += "[$sqlcolumnname] $sqldatatype"
				}

				$sql = "BEGIN CREATE TABLE $fqtn ($($sqldatatypes -join ' NULL,')) END"

				Write-Message -Level Debug -Message $sql

					if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating table $fqtn")) {
					try {
						$null = $server.Databases[$Database].ExecuteNonQuery($sql)
					}
					catch {
						Stop-Function -Message "The following query failed: $sql" -ErrorRecord $_
						return
					}
				}
			}
		}

			$rowcount = $InputObject.Rows.count
		if ($rowcount -eq 0) { $rowcount = 1 }

		if ($Pscmdlet.ShouldProcess($SqlInstance, "Writing $rowcount rows to $fqtn")) {
			$bulkCopy.WriteToServer($InputObject)
			if ($rowcount -is [int]) { Write-Progress -id 1 -activity "Inserting $rowcount rows" -status "Complete" -Completed }
		}
	}
	end {
		if ($bulkcopy) {
			$bulkcopy.Close()
			$bulkcopy.Dispose()
		}
	}
	}

