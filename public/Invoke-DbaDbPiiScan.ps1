function Invoke-DbaDbPiiScan {
    <#
    .SYNOPSIS
        Command to return any columns that could potentially contain PII (Personal Identifiable Information)

    .DESCRIPTION
        This command will go through the tables in your database and assess each column.
        It will first check the columns names if it was named in such a way that it would indicate PII.
        The next thing that it will do is pattern recognition by looking into the data from the table.
        Custom scan definitions can be specified using the formats seen in <dbatools module root>\bin\datamasking\pii-knownnames.json and <dbatools module root>\bin\datamasking\pii-patterns.json.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the databases to scan for potential PII data. Required parameter - at least one database must be specified.
        Use this to target specific databases rather than scanning entire SQL Server instances.

    .PARAMETER Table
        Limits the scan to specific tables within the target databases. Accepts multiple table names.
        Use this when you need to focus PII scanning on known tables containing sensitive data rather than scanning all tables.

    .PARAMETER Column
        Restricts the scan to specific columns within the target tables. Accepts multiple column names.
        Use this when you want to validate specific columns suspected of containing PII or to recheck previously identified columns.

    .PARAMETER Country
        Filters PII pattern matching to specific countries using full country names (e.g., "United States", "Canada").
        Use this when your data contains region-specific formats like phone numbers or postal codes that should only match certain countries.

    .PARAMETER CountryCode
        Filters PII pattern matching to specific countries using ISO country codes (e.g., "US", "CA", "GB").
        Use this for more precise regional filtering when you know the specific country codes for your data regions.

    .PARAMETER SampleCount
        Sets the number of data rows to examine per column for pattern matching. Default is 100 rows.
        Increase this value for more thorough scanning of large tables, or decrease it to speed up scans of tables with consistent data patterns.

    .PARAMETER KnownNameFilePath
        Specifies a JSON file path containing custom column name patterns that indicate PII data.
        Use this to add organization-specific column naming conventions that should be flagged as potential PII beyond the default patterns.

    .PARAMETER PatternFilePath
        Specifies a JSON file path containing custom regex patterns for identifying PII data within column values.
        Use this to add custom data patterns specific to your organization or industry that aren't covered by the default patterns.

    .PARAMETER ExcludeDefaultKnownName
        Disables the built-in column name patterns for PII detection, using only custom patterns if provided.
        Use this when the default column name patterns generate too many false positives for your specific database schema conventions.

    .PARAMETER ExcludeDefaultPattern
        Disables the built-in data value patterns for PII detection, using only custom patterns if provided.
        Use this when the default data patterns don't match your data formats or generate excessive false positives.

    .PARAMETER ExcludeTable
        Prevents scanning of specified tables even if they would otherwise be included in the scan scope.
        Use this to skip known system tables, staging tables, or tables confirmed to not contain PII data.

    .PARAMETER ExcludeColumn
        Prevents scanning of specified columns even if they would otherwise be included in the scan scope.
        Use this to skip columns like timestamps, IDs, or other fields confirmed to not contain PII data.

    .PARAMETER Force
        Forcefully execute commands when needed

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, GDPR, PII
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbPiiScan

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per detected PII finding across all scanned databases, tables, and columns. The result set includes classification information, masking recommendations, and detection method details.

        Properties returned for all findings:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database scanned
        - Schema: The schema name containing the table
        - Table: The table name containing the potential PII column
        - Column: The column name that was flagged as containing potential PII
        - PII-Category: Classification category for the PII data (e.g., Identity, Location, Contact)
        - PII-Name: Specific name of the PII type detected (e.g., SSN, Geography, Phone)
        - FoundWith: Detection method used - DataType, KnownName, or Pattern
        - MaskingType: Recommended type of data masking for this PII (e.g., Random, Shuffle, Partial)
        - MaskingSubType: Sub-type of the masking method (e.g., Decimal, String, Date)

        Additional properties based on detection method:

        When FoundWith = "Pattern" (pattern-matched data):
        - Country: Country filter applied to the pattern matching rule
        - CountryCode: ISO country code for the matched pattern
        - Pattern: The regex pattern that matched the data
        - Description: Human-readable description of the pattern

        When FoundWith = "KnownName" (column name match):
        - Pattern: The column name pattern that matched

        When FoundWith = "DataType" (geography type):
        - No additional properties beyond the standard set

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1

        Scan the database db1 on instance sql1

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1, sql2 -Database db1, db2

        Scan multiple databases on multiple instances

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db2 -ExcludeColumn firstname

        Scan database db2 but exclude the column firstname

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db2 -CountryCode US

        Scan database db2 but only apply data patterns used for the United States

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1 -PatternFilePath  c:\pii\patterns.json

        Scans db1 on instance sql1 with additional custom patterns

    .EXAMPLE
        Invoke-DbaDbPiiScan -SqlInstance sql1 -Database db1 -PatternFilePath  c:\pii\patterns.json -ExcludeDefaultPattern

        Scans db1 on instance sql1 with additional custom patterns, excluding the default patterns
    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Table,
        [string[]]$Column,
        [string[]]$Country,
        [string[]]$CountryCode,
        [string[]]$ExcludeTable,
        [string[]]$ExcludeColumn,
        [int]$SampleCount = 100,
        [string]$KnownNameFilePath,
        [string]$PatternFilePath ,
        [switch]$ExcludeDefaultKnownName,
        [switch]$ExcludeDefaultPattern,
        [switch]$EnableException
    )

    begin {
        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $defaultKnownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames = Get-Content -Path $defaultKnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $defaultPatternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $defaultPatternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath
            }
        }

        # Check parameters
        if (-not $SqlInstance) {
            Stop-Function -Message "Please enter a SQL Server instance" -Category InvalidArgument
        }

        if (-not $Database) {
            Stop-Function -Message "Please enter a database" -Category InvalidArgument
        }

        # Filter the patterns
        if ($Country.Count -ge 1) {
            $patterns = $patterns | Where-Object Country -In $Country
        }

        if ($CountryCode.Count -ge 1) {
            $patterns = $patterns | Where-Object CountryCode -In $CountryCode
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $piiScanResults = @()

        # Loop through the instances
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $progressActivity = "Scanning databases for PII"
            $progressId = 1

            # Loop through the databases
            foreach ($dbName in $Database) {

                $progressTask = "Scanning Database $dbName"
                Write-Progress -Id $progressId -Activity $progressActivity -Status $progressTask

                # Get the database object
                $db = $server.Databases[$($dbName)]

                # Filter the tables if needed
                if ($Table) {
                    $tables = $db.Tables | Where-Object Name -In $Table
                } else {
                    $tables = $db.Tables
                }

                if ($ExcludeTable) {
                    $tables = $tables | Where-Object Name -NotIn $ExcludeTable
                }

                # Filter the tables based on the column
                if ($Column) {
                    $tables = $tables | Where-Object { $ColumnNames = $_.Columns.Name; $Column | Where-Object { $_ -in $ColumnNames } }
                }

                $tableNumber = 1
                $progressStatusText = '"Table $($tableNumber.ToString().PadLeft($($tables.Count).Count.ToString().Length)) of $($tables.Count) | Scanning tables for database $dbName"'
                $progressStatusBlock = [ScriptBlock]::Create($progressStatusText)


                # Loop through the tables
                foreach ($tableobject in $tables) {
                    Write-Message -Level Verbose -Message "Scanning table [$($tableobject.Schema)].[$($tableobject.Name)]"

                    $progressTask = "Scanning columns and data"
                    Write-Progress -Id $progressId -Activity $progressActivity -Status (& $progressStatusBlock) -CurrentOperation $progressTask -PercentComplete ($tableNumber / $($tables.Count) * 100)

                    # Get the columns
                    if ($Column) {
                        $columns = $tableobject.Columns | Where-Object Name -In $Column
                    } else {
                        $columns = $tableobject.Columns
                    }

                    if ($ExcludeColumn) {
                        $columns = $columns | Where-Object Name -NotIn $ExcludeColumn
                    }

                    # Loop through the columns
                    foreach ($columnobject in $columns) {

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $piiScanResults += [PSCustomObject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $dbName
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {

                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($columnobject.Name -match $pattern) {
                                            # Add the column name match if not already found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $knownName.Category -and
                                                        $_."PII-Name" -eq $knownName.Name -and
                                                        $_.FoundWith -eq "KnownName" -and
                                                        $_.MaskingType -eq $knownName.MaskingType -and
                                                        $_.MaskingSubType -eq $knownName.MaskingSubType })) {

                                                $piiScanResults += [PSCustomObject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $knownName.Category
                                                    "PII-Name"     = $knownName.Name
                                                    FoundWith      = "KnownName"
                                                    MaskingType    = $knownName.MaskingType
                                                    MaskingSubType = $knownName.MaskingSubType
                                                    Pattern        = $knownName.Pattern
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on"
                            }

                            if ($patterns.Count -ge 1) {

                                Write-Message -Level Verbose -Message "Scanning the top $SampleCount values for [$($columnobject.Name)] from [$($tableobject.Schema)].[$($tableobject.Name)]"

                                # Set the text data types
                                $textDataTypes = 'char', 'varchar', 'nchar', 'nvarchar'

                                # Setup the query
                                if ($columnobject.DataType.Name -in $textDataTypes) {
                                    $query = "SELECT TOP($SampleCount) LTRIM(RTRIM([$($columnobject.Name)])) AS [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                                } else {
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] AS [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Get the data
                                try {
                                    $dataset = Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $dbName -Query $query -EnableException
                                } catch {
                                    $errormessage = $_.Exception.Message.ToString()
                                    Stop-Function -Message "Error executing query $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $updatequery -Continue -ErrorRecord $_
                                }

                                # Check if there is any data
                                if ($dataset.Count -ge 1) {

                                    # Loop through the patterns
                                    foreach ($patternobject in $patterns) {

                                        # If there is a result from the match
                                        if ($dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                            # Add the data match if not already found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $patternobject.category -and
                                                        $_."PII-Name" -eq $patternobject.Name -and
                                                        $_.FoundWith -eq "Pattern" -and
                                                        $_.MaskingType -eq $patternobject.MaskingType -and
                                                        $_.MaskingSubType -eq $patternobject.MaskingSubType -and
                                                        $_.Country -eq $patternobject.Country -and
                                                        $_.CountryCode -eq $patternobject.CountryCode })) {

                                                $piiScanResults += [PSCustomObject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                    Country        = $patternobject.Country
                                                    CountryCode    = $patternobject.CountryCode
                                                    Pattern        = $patternobject.Pattern
                                                    Description    = $patternobject.Description
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on"
                            }
                        }
                    }

                    $tableNumber++

                } # End for each table
            } # End for each database
            Write-Progress -Id $progressId -Activity $progressActivity -Completed
        } # End for each instance

        $piiScanResults
    } # End process
}
