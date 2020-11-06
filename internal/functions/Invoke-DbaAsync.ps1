function Invoke-DbaAsync {
    <#
        .SYNOPSIS
            Runs a T-SQL script.

        .DESCRIPTION
            Runs a T-SQL script. It's a stripped down version of https://github.com/sqlcollaborative/Invoke-SqlCmd2 and adapted to use dbatools' facilities.
            If you're looking for a public usable function, see Invoke-DbaQuery

        .PARAMETER SQLConnection
            Specifies an existing SQLConnection object to use in connecting to SQL Server.

        .PARAMETER Query
            Specifies one or more queries to be run. The queries can be Transact-SQL, XQuery statements, or sqlcmd commands. Multiple queries in a single batch may be separated by a semicolon.

            Do not specify the sqlcmd GO separator (or, use the ParseGo parameter). Escape any double quotation marks included in the string.

            Consider using bracketed identifiers such as [MyTable] instead of quoted identifiers such as "MyTable".

        .PARAMETER QueryTimeout
            Specifies the number of seconds before the queries time out.

        .PARAMETER As
            Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', 'PSObjectArray', and 'SingleValue'

            PSObject and PSObjectArray output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

        .PARAMETER SqlParameters
            Specifies a hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

            Example:

        .PARAMETER AppendServerInstance
            If this switch is enabled, the SQL Server instance will be appended to PSObject and DataRow output.


        .PARAMETER MessagesToOutput
            Use this switch to have on the output stream messages too (e.g. PRINT statements). Output will hold the resultset too. See examples for detail

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        .PARAMETER CommandType
            Specifies the type of command represented by the query string.  Default is Text
    #>

    param (
        [Alias('Connection', 'Conn')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.SqlServer.Management.Common.ServerConnection]$SQLConnection,

        [Parameter(Mandatory, ParameterSetName = "Query")]
        [string]
        $Query,

        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "PSObjectArray", "SingleValue")]
        [string]
        $As = "DataRow",

        [System.Collections.IDictionary]
        $SqlParameters,

        [System.Data.CommandType]
        $CommandType = 'Text',

        [switch]
        $AppendServerInstance,

        [Int32]$QueryTimeout = 600,

        [switch]
        $MessagesToOutput,

        [switch]$EnableException
    )

    begin {
        function Resolve-SqlError {
            param($Err)
            if ($Err) {
                if ($Err.Exception.GetType().Name -eq 'SqlException') {
                    # For SQL exception
                    #$Err = $_
                    Write-Message -Level Debug -Message "Capture SQL Error"
                    if ($PSBoundParameters.Verbose) {
                        Write-Message -Level Verbose -Message "SQL Error:  $Err"
                    } #Shiyang, add the verbose output of exception
                    switch ($ErrorActionPreference.ToString()) {
                        { 'SilentlyContinue', 'Ignore' -contains $_ } { }
                        'Stop' { throw $Err }
                        'Continue' { throw $Err }
                        Default { Throw $Err }
                    }
                } else {
                    # For other exception
                    Write-Message -Level Debug -Message "Capture Other Error"
                    if ($PSBoundParameters.Verbose) {
                        Write-Message -Level Verbose -Message "Other Error:  $Err"
                    }
                    switch ($ErrorActionPreference.ToString()) {
                        { 'SilentlyContinue', 'Ignore' -contains $_ } { }
                        'Stop' { throw $Err }
                        'Continue' { throw $Err }
                        Default { throw $Err }
                    }
                }
            }

        }

        if ($As -in "PSObject", "PSObjectArray") {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@

            try {
                if ($PSEdition -eq 'Core') {
                    $assemblies = @('System.Management.Automation', 'System.Data.Common', 'System.ComponentModel.TypeConverter')
                } else {
                    $assemblies = @('System.Data', 'System.Xml')
                }
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies $assemblies -ErrorAction stop
            } catch {
                if (-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*") {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_."
                    $As = "Datarow"
                }
            }
        }

        $GoSplitterRegex = [regex]'(?smi)^[\s]*GO[\s]*$'

    }
    process {
        $Conn = $SQLConnection.SqlConnectionObject


        Write-Message -Level Debug -Message "Stripping GOs from source"
        $Pieces = $GoSplitterRegex.Split($Query)

        # Only execute non-empty statements
        $Pieces = $Pieces | Where-Object { $_.Trim().Length -gt 0 }
        foreach ($piece in $Pieces) {
            $cmd = New-Object system.Data.SqlClient.SqlCommand($piece, $conn)
            $cmd.CommandType = $CommandType
            $cmd.CommandTimeout = $QueryTimeout

            if ($null -ne $SqlParameters) {
                $SqlParameters.GetEnumerator() | ForEach-Object {
                    if ($null -ne $_.Value) {
                        $cmd.Parameters.AddWithValue($_.Key, $_.Value)
                    } else {
                        $cmd.Parameters.AddWithValue($_.Key, [DBNull]::Value)
                    }
                } > $null
            }

            $ds = New-Object system.Data.DataSet
            $da = New-Object system.Data.SqlClient.SqlDataAdapter($cmd)

            if ($MessagesToOutput) {
                $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
                $pool = [RunspaceFactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS + 1)
                $pool.ApartmentState = "MTA"
                $pool.Open()
                $runspaces = @()
                $scriptBlock = {
                    param ($da, $ds, $conn, $queue )
                    $conn.FireInfoMessageEventOnUserErrors = $false
                    $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { $queue.Enqueue($_) }
                    $conn.add_InfoMessage($handler)
                    $Err = $null
                    try {
                        [void]$da.fill($ds)
                    } catch {
                        $Err = $_
                    } finally {
                        $conn.remove_InfoMessage($handler)
                    }
                    return $Err
                }
                $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
                $runspace = [PowerShell]::Create()
                $null = $runspace.AddScript($scriptBlock)
                $null = $runspace.AddArgument($da)
                $null = $runspace.AddArgument($ds)
                $null = $runspace.AddArgument($Conn)
                $null = $runspace.AddArgument($queue)
                $runspace.RunspacePool = $pool
                $runspaces += [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }
                # While streaming ...
                while ($runspaces.Status.IsCompleted -notcontains $true) {
                    $item = $null
                    if ($queue.TryDequeue([ref]$item)) {
                        "$item"
                    }
                }
                # Drain the stream as the runspace is closed, just to be safe
                if ($queue.IsEmpty -ne $true) {
                    $item = $null
                    while ($queue.TryDequeue([ref]$item)) {
                        "$item"
                    }
                }
                foreach ($runspace in $runspaces) {
                    $results = $runspace.Pipe.EndInvoke($runspace.Status)
                    $runspace.Pipe.Dispose()
                    if ($null -ne $results) {
                        Resolve-SqlError $results[0]
                    }
                }
                $pool.Close()
                $pool.Dispose()
                [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
            } else {
                #Following EventHandler is used for PRINT and RAISERROR T-SQL statements. Executed when -Verbose parameter specified by caller and no -MessageToOutput
                if ($PSBoundParameters.Verbose) {
                    $conn.FireInfoMessageEventOnUserErrors = $false
                    $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { Write-Verbose -Message "$($_)" }
                    $conn.add_InfoMessage($handler)
                }
                try {
                    [void]$da.fill($ds)
                } catch {
                    $Err = $_
                } finally {
                    if ($PSBoundParameters.Verbose) {
                        $conn.remove_InfoMessage($handler)
                    }
                }
                Resolve-SqlError $Err
            }
            if ($AppendServerInstance) {
                #Basics from Chad Miller
                $Column = New-Object Data.DataColumn
                $Column.ColumnName = "ServerInstance"

                if ($ds.Tables.Count -ne 0) {
                    $ds.Tables[0].Columns.Add($Column)
                    Foreach ($row in $ds.Tables[0]) {
                        $row.ServerInstance = $SQLConnection.ServerInstance
                    }
                }
            }

            switch ($As) {
                'DataSet' {
                    $ds
                }
                'DataTable' {
                    $ds.Tables
                }
                'DataRow' {
                    if ($ds.Tables.Count -ne 0) {
                        $ds.Tables[0]
                    }
                }
                'PSObject' {
                    foreach ($table in $ds.Tables) {
                        #Scrub DBNulls - Provides convenient results you can use comparisons with
                        #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                        foreach ($row in $table.Rows) {
                            [DBNullScrubber]::DataRowToPSObject($row)
                        }
                    }
                }
                'PSObjectArray' {
                    foreach ($table in $ds.Tables) {
                        $rows = foreach ($row in $table.Rows) {
                            [DBNullScrubber]::DataRowToPSObject($row)
                        }
                        , $rows
                    }
                }
                'SingleValue' {
                    if ($ds.Tables.Count -ne 0) {
                        $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                    }
                }
            }
        } #foreach ($piece in $Pieces)

    }
}
