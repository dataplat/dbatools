function Copy-DbaTableData {
    <#
        .SYNOPSIS
            Copies data between SQL Server tables.

        .DESCRIPTION
            Copies data between SQL Server tables using SQL Bulk Copy.
            The same can be achieved also doing
                $sourcetable = Invoke-SqlCmd2 -ServerInstance instance1 ... -As DataTable
                Write-DbaDataTable -SqlInstance ... -InputObject $sourcetable
            but it will force buffering the contents on the table in memory (high RAM usage for large tables).
            With this function, a streaming copy will be done in the most speedy and least resource-intensive way.

        .PARAMETER SqlInstance
            Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
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

        .PARAMETER DestinationDatabase
            The database to copy the table to. If not specified, it is assumed to be the same of Database

        .PARAMETER Table
            Define a specific table you would like to use as source. You can specify up to three-part name like db.sch.tbl.
            If the object has special characters please wrap them in square brackets [ ].
            This dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
            The correct way to find table named 'First.Table' on schema 'dbo' is passing dbo.[First.Table]

        .PARAMETER DestinationTable
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
            Copy-DbaTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table test_table

            Copies all the data from sql1 to sql2, using the database dbatools_from.

        .EXAMPLE
            Copy-DbaTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -DatabaseDest dbatools_dest -Table test_table

            Copies all the data from sql1 to sql2, using the database dbatools_from as source and dbatools_dest as destination

        .EXAMPLE
            Get-DbaTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaTableData -DestinationTable tb3

            Copies all data from tables tb1 and tb2 in tempdb on sql1 to tb3 in tempdb onsql1

        .EXAMPLE
            Get-DbaTable -SqlInstance sql1 -Database tempdb -Table tb1, tb2 | Copy-DbaTableData -Destination sql2

            Copies data from tbl1 in tempdb on sql1 to tbl1 in tempdb on sql2
            then
            Copies data from tbl2 in tempdb on sql1 to tbl2 in tempdb on sql2

        .EXAMPLE
            Copy-DbaTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table test_table

            Copies all the data from sql1 to sql2, using the database dbatools_from.

        .EXAMPLE
            Copy-DbaTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table test_table -KeepIdentity -Truncate

            Copies all the data from sql1 to sql2, using the database dbatools_from, keeping identity columns and truncating the destination

        .EXAMPLE
            Copy-DbaTableData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -Table test_table -KeepIdentity -Truncate

            Copies all the data from sql1 to sql2, using the database dbatools_from, keeping identity columns and truncating the destination

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [Alias("ServerInstance", "SqlServer", "Source")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string]$Database,
        [string]$DestinationDatabase,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Table,
        [string]$Query,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 5000,
        [string]$DestinationTable,
        [switch]$NoTableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [switch]$Truncate,
        [int]$bulkCopyTimeOut = 5000,
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
    }

    process {

        if ($SqlInstance) {

            if ((Test-Bound -Not -ParameterName Database)) {
                Stop-Function -Message "Database is required when passing a SqlInstance" -Target $Table
                return
            }

            $tablecollection = [Microsoft.SqlServer.Management.Smo.Table[]]$tablecollection

            try {
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            if ($Database -notin $server.Databases.Name) {
                Stop-Function -Message "Database $Database doesn't exist on $server"
                return
            }

            try {
                $tablecollection += Get-DbaTable -SqlInstance $server -Table $Table -Database $Database -EnableException -Verbose:$false
            }
            catch {
                Stop-Function -Message "Unable to determine source table : $Table"
                return
            }
        }

        if (-not $tablecollection) {
            $tablecollection = [Microsoft.SqlServer.Management.Smo.Table[]]$Table
        }

        foreach ($sqltable in $tablecollection) {

            $Database = $sqltable.Parent.Name
            $server = $sqltable.Parent.Parent

            if ((Test-Bound -Not -ParameterName DestinationDatabase)) {
                $DestinationDatabase = $Database
            }

            if ((Test-Bound -Not -ParameterName DestinationTable)) {
                $DestinationTable = $sqltable.Name
            }

            if ((Test-Bound -Not -ParameterName Destination)) {
                $destServer = $server
            }
            else {
                try {
                    $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
                    return
                }
            }

            if ($DestinationDatabase -notin $destServer.Databases.Name) {
                Stop-Function -Message "Database $DestinationDatabase doesn't exist on $destServer"
                return
            }

            try {
                $desttable = Get-DbaTable -SqlInstance $destServer -Table $DestinationTable -Database $Database -EnableException -Verbose:$false | Select-Object -First 1
            }
            catch {
                Stop-Function -Message "Unable to determine destination table: $DestinationTable"
                return
            }

            if (-not $desttable) {
                Stop-Function -Message "$DestinationTable does not exist on destination"
                return
            }

            $connstring = $destServer.ConnectionContext.ConnectionString

            $fqtnfrom = "$($server.Databases[$Database]).$sqltable"
            $fqtndest = "$($destServer.Databases[$DestinationDatabase]).$desttable"

            if (Test-Bound -ParameterName Query -Not) {
                $Query = "SELECT * FROM $fqtnfrom"
            }

            if ($Truncate -eq $true) {
                if ($Pscmdlet.ShouldProcess($destServer, "Truncating table $fqtndest")) {
                    $null = $destServer.Databases[$DestinationDatabase].ExecuteNonQuery("TRUNCATE TABLE $fqtndest")
                }
            }
            $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
            $cmd.CommandText = $Query
            $server.ConnectionContext.SqlConnectionObject.Open()
            $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy("$connstring;Database=$DestinationDatabase", $bulkCopyOptions)
            $bulkCopy.DestinationTableName = $fqtndest
            $bulkCopy.EnableStreaming = $true
            $bulkCopy.BatchSize = $BatchSize
            $bulkCopy.NotifyAfter = $NotifyAfter
            $bulkCopy.BulkCopyTimeOut = $BulkCopyTimeOut

            $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            # Add RowCount output
            $bulkCopy.Add_SqlRowsCopied( {
                    $RowsPerSec = [math]::Round($args[1].RowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)
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

            [pscustomobject]@{
                SourceInstance      = $server.Name
                SourceDatabase      = $Database
                SourceTable         = $sqltable.Name
                DestinationInstance = $destServer.name
                DestinationDatabase = $DestinationDatabase
                DestinationTable    = $desttable.Name
                RowsCopied          = $rowstotal
                Elapsed             = [prettytimespan]$elapsed.Elapsed
            }
        }
    }
}