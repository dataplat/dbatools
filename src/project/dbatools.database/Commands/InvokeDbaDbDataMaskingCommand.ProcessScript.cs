#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop process-script (concatenated parts) - split per the repo 400-line file limit.
public sealed partial class InvokeDbaDbDataMaskingCommand
{
    // The verbatim process body exceeds the 400-line file law; it is carried as compile-time
    // concatenated const parts (byte-identical composition to the original single literal).
    private const string ProcessScript = ProcessScriptPart1 + "\n" + ProcessScriptPart2 + "\n" + ProcessScriptPart3 + "\n" + ProcessScriptPart4;

    private const string ProcessScriptPart1 = """
param($SqlInstance, $SqlCredential, $Database, $FilePath, $Locale, $CharacterString, $Table, $Column, $ExcludeTable, $ExcludeColumn, $MaxValue, $DictionaryFilePath, $DictionaryExportPath, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundMaxValue, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, $FilePath, [string]$Locale, [string]$CharacterString, [string[]]$Table, [string[]]$Column, [string[]]$ExcludeTable, [string[]]$ExcludeColumn, [int]$MaxValue, [string[]]$DictionaryFilePath, [string]$DictionaryExportPath, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundMaxValue, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-hop results: the supported type lists and defaulted ints the source computed once
    $supportedDataTypes = $__beginState.SupportedDataTypes
    $supportedFakerMaskingTypes = $__beginState.SupportedFakerMaskingTypes
    $supportedFakerSubTypes = $__beginState.SupportedFakerSubTypes
    $ModulusFactor = $__beginState.ModulusFactor
    $CommandTimeout = $__beginState.CommandTimeout
    $BatchSize = $__beginState.BatchSize
    $Retry = $__beginState.Retry

    # the source's begin ConfirmPreference effect: $Force (undeclared) was resolved ONCE in the
    # begin hop and carried, so a mid-pipeline change to an upstream $Force cannot alter
    # confirmation behavior between records - exactly the function's run-once begin semantics
    if ($__beginState.BeginForce) { $ConfirmPreference = 'none' }

    # cross-record function-scope locals: restore only what an earlier record assigned
    if ($null -ne $__state) {
        foreach ($__name in "identityColumn", "convertedValue", "lookupResult", "charstring", "min", "max", "columnobject", "maskingErrorFlag", "dictionaryFileName", "Database", "insertValue") {
            if ($__state[$__name + "Assigned"]) { Set-Variable -Name $__name -Value $__state[$__name] }
        }
    }

    # ATTRIBUTION SHIM (the Get-PSCallStack class): Write-ProgressHelper reads
    # (Get-PSCallStack)[1].Command; routing both call sites through this named wrapper shows it
    # the real command name instead of the generated scriptblock frame.
    function Invoke-DbaDbDataMasking { param($__progressParams) Write-ProgressHelper @__progressParams }

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Test the configuration file
            try {
                $configErrors = @()

                $configErrors += Test-DbaDbDataMaskingConfig -FilePath $FilePath -EnableException

                if ($configErrors.Count -ge 1) {
                    Stop-Function -Message "Errors found testing the configuration file." -Target $FilePath -FunctionName Invoke-DbaDbDataMasking
                    return $configErrors
                }
            } catch {
                Stop-Function -Message "Something went wrong testing the configuration file" -ErrorRecord $_ -Target $FilePath -FunctionName Invoke-DbaDbDataMasking
                return
            }

            # Get all the items that should be processed
            try {
                $tables = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath -FunctionName Invoke-DbaDbDataMasking
                return
            }
        }

        # Test the columns for data types
        foreach ($tabletest in $tables.Tables) {
            if ($Table -and $tabletest.Name -notin $Table) {
                continue
            }

            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml', 'geometry' -and $columntest.Name -notin $Column) {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables -Continue -FunctionName Invoke-DbaDbDataMasking
                }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbDataMasking
            }

            # Check if the deterministic values table is already present
            if ($server.Databases['tempdb'].Tables.Name -contains 'DeterministicValues') {
                Write-Message -Level Verbose -Message "Deterministic values table already exists. Dropping it...." -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                $query = "DROP TABLE [dbo].[DeterministicValues];"
                $server.Databases['tempdb'].Query($query)
            }

            # Create the deterministic value table
            $query = "
                CREATE TABLE dbo.DeterministicValues
                (
                    [ValueKey] VARCHAR(900),
                    [NewValue] VARCHAR(900)
                )

                CREATE UNIQUE NONCLUSTERED INDEX UNX__DeterministicValues_ValueKey
                ON dbo.DeterministicValues ( ValueKey )
            "

            $null = $server.Databases['tempdb'].Query($query)

            # Import the dictionary files
            if ($DictionaryFilePath.Count -ge 1) {
                foreach ($file in $DictionaryFilePath) {
                    Write-Message -Level Verbose -Message "Importing dictionary file '$file'" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                    if (Test-Path -Path $file) {
                        try {
                            # Import the keys and values
                            Import-DbaCsv -Path $file -SqlInstance $server -Database tempdb -Schema dbo -Table DeterministicValues
                        } catch {
                            Stop-Function -Message "Could not import csv data from file '$file'" -ErrorRecord $_ -Target $file -FunctionName Invoke-DbaDbDataMasking
                        }
                    } else {
                        Stop-Function -Message "Could not import dictionary file '$file'" -Target $file -FunctionName Invoke-DbaDbDataMasking
                    }
                }
            }

            # Get the database name
            if (-not $Database) {
                $Database = $tables.Name
            }

            # Loop through the databases
            foreach ($dbName in $Database) {
                if ($server.VersionMajor -lt 9) {
                    Stop-Function -Message "SQL Server version must be 2005 or greater" -Continue -FunctionName Invoke-DbaDbDataMasking
                }

                $db = $server.Databases[$($dbName)]

                $nullmod = 0

                #region for each table
                foreach ($tableobject in $tables.Tables) {
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                    $uniqueDataTableName = $null
                    $uniqueValueColumns = @()
                    $stringBuilder = [System.Text.StringBuilder]''

                    if ($tableobject.Name -in $ExcludeTable) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -Continue -FunctionName Invoke-DbaDbDataMasking
                    }

                    $dbTable = $db.Tables | Where-Object { $_.Schema -eq $tableobject.Schema -and $_.Name -eq $tableobject.Name }

                    [bool]$cleanupIdentityColumn = $false
                    [bool]$cleanupMaskingIndex = $false

                    # The masking index name used for cleanup checks
                    $maskingIndexName = "NIX__$($dbTable.Schema)_$($dbTable.Name)_Masking"

                    # Make sure there is an identity column present to speed things up
                    # Skip column and index creation when -WhatIf is active to avoid leaving behind schema changes
                    if (-not $WhatIfPreference) {
                        if (-not ($dbTable.Columns | Where-Object { $_.Identity -eq $true })) {
                            Write-Message -Level Verbose -Message "Adding identity column to table [$($dbTable.Schema)].[$($dbTable.Name)]" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                            $query = "ALTER TABLE [$($dbTable.Schema)].[$($dbTable.Name)] ADD MaskingID BIGINT IDENTITY(1, 1) NOT NULL;"

                            try {
                                Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database $db.Name -Query $query
                            } catch {
                                Stop-Function -Message "Could not alter the table to add the masking id" -Target $db -Continue -FunctionName Invoke-DbaDbDataMasking
                            }

                            $cleanupIdentityColumn = $true

                            $identityColumn = "MaskingID"

                            $dbTable.Columns.Refresh()
                        } else {
                            $identityColumn = $dbTable.Columns | Where-Object { $_.Identity } | Select-Object -ExpandProperty Name
                        }

                        # Check if the index for the identity column is already present
                        try {
                            if ($dbTable.Indexes.Name -contains $maskingIndexName) {
                                Write-Message -Level Verbose -Message "Masking index already exists in table [$($dbTable.Schema)].[$($dbTable.Name)]. Dropping it..." -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                                $dbTable.Indexes[$($maskingIndexName)].Drop()
                            }
                        } catch {
                            Stop-Function -Message "Could not remove identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue -FunctionName Invoke-DbaDbDataMasking
                        }

                        # Create the index for the identity column
                        try {
                            Write-Message -Level Verbose -Message "Adding index on identity column [$($identityColumn)] in table [$($dbTable.Schema)].[$($dbTable.Name)]" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"

                            $query = "CREATE NONCLUSTERED INDEX [$($maskingIndexName)] ON [$($dbTable.Schema)].[$($dbTable.Name)]([$($identityColumn)])"

                            $queryParams = @{
                                SqlInstance   = $server
                                SqlCredential = $SqlCredential
                                Database      = $db.Name
                                Query         = $query
                                QueryTimeout  = $CommandTimeout
                            }

                            Invoke-DbaQuery @queryParams
                            $cleanupMaskingIndex = $true
                        } catch {
                            Stop-Function -Message "Could not add identity index to table [$($dbTable.Schema)].[$($dbTable.Name)]" -Continue -FunctionName Invoke-DbaDbDataMasking
                        }
                    }

                    $actionIdentityValues = @()

                    try {
                        if ($WhatIfPreference) {
                            # In WhatIf mode, only get the row count without modifying the table structure
                            if ($tableobject.FilterQuery) {
                                $trimmedFilterQuery = ($tableobject.FilterQuery).Trim()

                                if ($trimmedFilterQuery.EndsWith(";")) {
                                    $trimmedFilterQuery = $trimmedFilterQuery.Substring(0, $trimmedFilterQuery.Length - 1)
                                }

                                $query = "SELECT COUNT(*) AS RowCount FROM ($trimmedFilterQuery) AS [dbatools_masking_source]"
                            } else {
                                $query = "SELECT COUNT(*) AS RowCount FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                            }

                            $rowCount = ($db.Query($query)).RowCount
                            $data = New-Object object[] $rowCount
                        } elseif (-not $tableobject.FilterQuery) {
                            # Get all the columns from the table
                            $columnString = "[" + (($dbTable.Columns | Where-Object { $_.DataType -in $supportedDataTypes } | Select-Object Name -ExpandProperty Name) -join "],[") + "]"

                            # Add the identifier column
                            $columnString += ",[$($identityColumn)]"

                            # Put it all together
                            $query = "SELECT $($columnString) FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                            # Get the data
                            [array]$data = $db.Query($query)
                        } else {
                            # Get the query from the table objects
                            $query = ($tableobject.FilterQuery).ToLower()

                            # Check if the query already contains the identifier column
                            if (-not ($query | Select-String -Pattern $identityColumn)) {
                                # Split up the query from the first "FROM"
                                $queryParts = $query -split "FROM", 2

                                # Put it all together again with the identifier
                                $query = "$($queryParts[0].Trim()), $($identityColumn) FROM $($queryParts[1].Trim())"
                            }

                            # Get the data
                            [array]$data = $db.Query($query)

                            $actionIdentityValues = @($data | ForEach-Object { $PSItem.$identityColumn } | Where-Object { $null -ne $PSItem } | Select-Object -Unique)
                        }
                    } catch {
                        Stop-Function -Message "Failure retrieving the data from table [$($tableobject.Schema)].[$($tableobject.Name)]" -Target $Database -ErrorRecord $_ -Continue -FunctionName Invoke-DbaDbDataMasking
                    }

                    #region unique indexes
                    # Check if the table contains unique indexes
                    if ($WhatIfPreference -and $tableobject.HasUniqueIndex) {
                        Write-Message -Level Verbose -Message "Skipping unique value preparation for [$($tableobject.Schema)].[$($tableobject.Name)] because -WhatIf is active" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                    } elseif ($tableobject.HasUniqueIndex) {

                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for [$($tableobject.Schema)].[$($tableobject.Name)]" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"

                        $params = @{
                            SqlInstance   = $server
                            SqlCredential = $SqlCredential
                            Database      = $db.name
                            Schema        = $tableobject.Schema
                            Table         = $tableobject.Name
                        }

                        $indexToTable = Convert-DbaIndexToTable @params

                        if ($indexToTable) {
                            # compare the index columns to the column in the json table object
                            $compareParams = @{
                                ReferenceObject  = $indexToTable.Columns
                                DifferenceObject = $tableobject.Columns.Name
                                IncludeEqual     = $true
                            }
                            $maskingColumnIndexCount = (Compare-Object @compareParams | Where-Object { $_.SideIndicator -eq "==" }).Count

                            # Check if there is any need to generate unique values
                            if ($maskingColumnIndexCount -ge 1) {

                                # Check if the temporary table already exists
                                $server.Databases['tempdb'].Tables.Refresh()
                                $uniqueDataTableName = $indexToTable.TempTableName

                                if ($server.Databases['tempdb'].Tables.Name -contains $indexToTable.TempTableName) {
                                    Write-Message -Level Verbose -Message "Table '$($indexToTable.TempTableName)' already exists. Dropping it.." -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                                    try {
                                        $query = "DROP TABLE $($indexToTable.TempTableName)"
                                        Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $query
                                    } catch {
                                        Stop-Function -Message "Could not drop temporary table" -FunctionName Invoke-DbaDbDataMasking
                                    }
                                }

                                # Create the temporary table
                                try {
                                    Write-Message -Level Verbose -Message "Creating temporary table '$($indexToTable.TempTableName)'" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
                                    Invoke-DbaQuery -SqlInstance $server -SqlCredential $SqlCredential -Database 'tempdb' -Query $indexToTable.CreateStatement
                                } catch {
                                    Stop-Function -Message "Could not create temporary table #[$($tableobject.Schema)].[$($tableobject.Name)]" -FunctionName Invoke-DbaDbDataMasking
                                }

                                # Create the unique index table
                                try {
                                    Write-Message -Level Verbose -Message "Creating the unique index for temporary table '$($indexToTable.TempTableName)'" -FunctionName Invoke-DbaDbDataMasking -ModuleName "dbatools"
""";
}
