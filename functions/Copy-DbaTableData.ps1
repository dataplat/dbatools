function Copy-DbaTableData {
	<#
		.SYNOPSIS
			Copies data between SQL Server tables.

		.DESCRIPTION
			Copies data between SQL Server tables using SQL Bulk Copy.
			The same can be achieved also doing
				$sourceTable = Invoke-SqlCmd2 -ServerInstance instance1 ... -As DataTable
				Write-DbaDataTable -SqlInstance ... -InputObject $sourceTable
			but it will force buffering the contents on the table in memory (high RAM usage for large tables).
			With this function, a streaming copy will be done in the most speedy and least resource-intensive way.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			The database to copy the table from.

		.PARAMETER DatabaseDest
			The database to copy the table to. If not specified, it is assumed to be the same of Database

		.PARAMETER Table
			Define a specific table you would like to use as source. You can specify up to three-part name like db.sch.tbl.
            If the object has special characters please wrap them in square brackets [ ].
            This dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
			The correct way to find table named 'First.Table' on schema 'dbo' is passing dbo.[First.Table]

		.PARAMETER TableDest
			The table you want to use as destination. If not specified, it is assumed to be the same of Table

		.PARAMETER Query
			If you want to copy only a portion, specify the query (but please, select all the columns, or nasty things will happen)

		.PARAMETER BatchSize
			The BatchSize for the import defaults to 5000.

		.PARAMETER NotifyAfter
			Sets the option to show the notification after so many rows of import

		.PARAMETER NoTableLock
			If this switch is enabled, a table lock (TABLOCK) will not be placed on the destination table. By default, this operation will lock the destination table while running.

		.PARAMETER CheckConstraints
			If this switch is enabled, the SqlBulkCopy option to process check constraints will be enabled.

			Per Microsoft "Check constraints while data is being inserted. By default, constraints are not checked."

		.PARAMETER FireTriggers
			If this switch is enabled, the SqlBulkCopy option to fire insert triggers will be enabled.

			Per Microsoft "When specified, cause the server to fire the insert triggers for the rows being inserted into the Database."

		.PARAMETER KeepIdentity
			If this switch is enabled, the SqlBulkCopy option to preserve source identity values will be enabled.

			Per Microsoft "Preserve source identity values. When not specified, identity values are assigned by the destination."

		.PARAMETER KeepNulls
			If this switch is enabled, the SqlBulkCopy option to preserve NULL values will be enabled.

			Per Microsoft "Preserve null values in the destination table regardless of the settings for default values. When not specified, null values are replaced by default values where applicable."

		.PARAMETER Truncate
			If this switch is enabled, the destination table will be truncated after prompting for confirmation.

		.PARAMETER BulkCopyTimeOut
			Value in seconds for the BulkCopy operations timeout. The default is 30 seconds.

		.PARAMETER RegularUser
			If this switch is enabled, the user connecting to the source will be assumed to be a non-administrative user. By default, the underlying connection assumes that the user has administrative privileges.

			This is particularly important when connecting to a SQL Azure Database.

		.PARAMETER RegularUserDest
			Same as RegularUser, but for the destination


		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

		.NOTES
			Tags: Migration
			Author: niphlod (Simone Bizzotto)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaTableData

		.EXAMPLE
			Copy-DbaTableData -Source sqlserver2014a -Destination sqlserver2016a -Database dbatools_from -Table test_table

			Copies all the data from sqlserver2014a to sqlserver2016a, using the database dbatools_from.

		.EXAMPLE
			Copy-DbaTableData -Source sqlserver2014a -Destination sqlserver2016a -Database dbatools_from -DatabaseDest dbatools_dest -Table test_table

			Copies all the data from sqlserver2014a to sqlserver2016a, using the database dbatools_from as source and dbatools_dest as destination

		.EXAMPLE
			Copy-DbaTableData -Source sqlserver2014a -Destination sqlserver2016a -Database dbatools_from -Table test_table

			Copies all the data from sqlserver2014a to sqlserver2016a, using the database dbatools_from.

		.EXAMPLE
			Copy-DbaTableData -Source sqlserver2014a -Destination sqlserver2016a -Database dbatools_from -Table test_table -KeepIdentity -Truncate

			Copies all the data from sqlserver2014a to sqlserver2016a, using the database dbatools_from, keeping identity columns and truncating the destination

		.EXAMPLE
			Copy-DbaTableData -Source sqlserver2014a -Destination sqlserver2016a -Database dbatools_from -Table test_table -KeepIdentity -Truncate

			Copies all the data from sqlserver2014a to sqlserver2016a, using the database dbatools_from, keeping identity columns and truncating the destination

	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential]$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential]$DestinationSqlCredential,
		[Parameter(Mandatory)]
		[string]$Database,
		[string]$DatabaseDest,
		[Parameter(Mandatory)]
		[string]$Table,
		[string]$Query,
		[int]$BatchSize = 50000,
		[int]$NotifyAfter = 5000,
		[string]$TableDest,
		[switch]$NoTableLock,
		[switch]$CheckConstraints,
		[switch]$FireTriggers,
		[switch]$KeepIdentity,
		[switch]$KeepNulls,
		[switch]$Truncate,
		[int]$bulkCopyTimeOut = 5000,
		[switch]$RegularUser,
		[switch]$RegularUserDest,
		[switch]$EnableException
	)

	begin {
		# Getting the total rows copied is a challenge. Use SqlBulkCopyExtension.
		# http://stackoverflow.com/questions/1188384/sqlbulkcopy-row-count-when-complete

		$sourcecode = 'namespace System.Data.SqlClient {
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

		Add-Type -ReferencedAssemblies System.Data.dll -TypeDefinition $sourcecode -ErrorAction SilentlyContinue
		$bulkCopyOptions = 0
		$options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default"

		foreach ($option in $options) {
			$optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
			if ($option -eq "TableLock" -and (!$NoTableLock)) {
				$optionValue = $true
			}
			if ($optionValue -eq $true) {
				$bulkCopyOptions += $([Data.SqlClient.SqlBulkCopyOptions]::$option).value__
			}
        }
        if ($TableDest.Length -eq 0) {
			$TableDest = $Table
		}
		if ($DatabaseDest.Length -eq 0) {
			$DatabaseDest = $Database
		}
	}

    process {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -RegularUser:$RegularUser
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        try {
            $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -RegularUser:$RegularUserDest
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
            return
		}

		if ($Database -notin $sourceServer.Databases.Name) {
			Stop-Function -Message "Database $Database doesn't exist on $sourceServer"
			return
		}
		if ($DatabaseDest -notin $destServer.Databases.Name) {
			Stop-Function -Message "Database $DatabaseDest doesn't exist on $destServer"
			return
		}
        try {
            $sourcetable = Get-DbaTable -SqlInstance $sourceServer -Table $Table -Database $Database -EnableException -Verbose:$false | Select-Object -First 1
        } catch {
            Stop-Function -Message "Unable to determine source table : $Table"
			return
        }

        try {
            $desttable = Get-DbaTable -SqlInstance $destServer -Table $TableDest -Database $Database -EnableException -Verbose:$false | Select-Object -First 1
        } catch {
            Stop-Function -Message "Unable to determine destination table: $TableDest"
			return
        }

		$connstring = $destServer.ConnectionContext.ConnectionString

        $fqtnfrom = "$($sourceServer.Databases[$Database]).$sourcetable"
        $fqtndest = "$($destServer.Databases[$DatabaseDest]).$desttable"

        if (-not $Query) {
            $Query = "SELECT * FROM $fqtnfrom"
        }

		if (-not $sourcetable) {
			Stop-Function -Message "$Table does not exist on source"
			return
        }
        if (-not $desttable) {
			Stop-Function -Message "$TableDest does not exist on destination"
			return
        }
		if ($Truncate -eq $true) {
			if ($Pscmdlet.ShouldProcess($destServer, "Truncating table $fqtndest")) {
				$null = $destServer.Databases[$DatabaseDest].Query("TRUNCATE TABLE $fqtndest")
			}
		}
		$cmd = $sourceServer.ConnectionContext.SqlConnectionObject.CreateCommand()
		$cmd.CommandText = $Query
		$sourceServer.ConnectionContext.SqlConnectionObject.Open()
		$bulkCopy = New-Object Data.SqlClient.SqlBulkCopy("$connstring;Database=$DatabaseDest", $bulkCopyOptions)
		$bulkCopy.DestinationTableName = $fqtndest
		$bulkCopy.EnableStreaming = $true
		$bulkCopy.BatchSize = $BatchSize
		$bulkCopy.NotifyAfter = $NotifyAfter
		$bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		# Add RowCount output
		$bulkCopy.Add_SqlRowsCopied({
				$RowsPerSec = [math]::Round($args[1].RowsCopied/$elapsed.ElapsedMilliseconds*1000.0, 1)
				Write-Progress -id 1 -activity "Inserting rows" -Status ([System.String]::Format("{0} rows ({1} rows/sec)", $args[1].RowsCopied, $RowsPerSec))
			})

		if ($Pscmdlet.ShouldProcess($destServer, "Writing rows to $fqtndest")) {
			$bulkCopy.WriteToServer($cmd.ExecuteReader())
			$RowsTotal = [System.Data.SqlClient.SqlBulkCopyExtension]::RowsCopiedCount($bulkCopy)
			$TotalTime = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
			Write-Message -Level Verbose -Message "$RowsTotal rows inserted in $TotalTime sec"
			if ($rowCount -is [int]) {
				Write-Progress -id 1 -activity "Inserting rows" -status "Complete" -Completed
			}
		}

		$bulkCopy.Close()
		$bulkCopy.Dispose()
	}
}