function Invoke-DbaDbPiiScan {
    <#
    .SYNOPSIS
        Command to return any columns that could potentially contain PII (Personal Identifiable Information)

    .DESCRIPTION
        This command will go through the tables in your database and assess each column.
        It will first check the columns names if it was named in such a way that it would indicate PII.
        The next thing that it will do is pattern recognition by looking into the data from the table.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Databases to process through

    .PARAMETER Table
        Table(s) to process. By default all the tables will be processed

    .PARAMETER Column
        Column(s) to process. By default all the columns will be processed

    .PARAMETER Country
        Filter out the patterns and known types for one or more countries

    .PARAMETER CountryCode
        Filter out the patterns and known types for one or more country code

    .PARAMETER SampleCount
        Amount of rows to sample to make an assessment. The default is 100

    .PARAMETER KnownNameFilePath
        Points to a file containing the custom known names

    .PARAMETER PatternFilePath
        Points to a file containing the custom patterns

    .PARAMETER ExcludeDefaultKnownName
        Excludes the default known names

    .PARAMETER ExcludeDefaultPattern
        Excludes the default patterns

    .PARAMETER ExcludeTable
        Exclude certain tables

    .PARAMETER ExcludeColumn
        Exclude certain columns

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
        Tags: Data Masking, Database, Personal Information, GDPR
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbPiiScan

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
                $knownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames += Get-Content -Path $knownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $patternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $patternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
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
            $patterns = $patterns | Where-Object Country -in $Country
        }

        if ($CountryCode.Count -ge 1) {
            $patterns = $patterns | Where-Object CountryCode -in $CountryCode
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        # Loop through the instances
        foreach ($instance in $SqlInstance) {

            # Try to connect to the server
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    $tables = $db.Tables | Where-Object Name -in $Table
                } else {
                    $tables = $db.Tables
                }

                if ($ExcludeTable) {
                    $tables = $tables | Where-Object Name -notin $ExcludeTable
                }

                # Filter the tables based on the column
                if ($Column) {
                    $tables = $tables | Where-Object { $_.Columns.Name -in $Column }
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
                        $columns = $tableobject.Columns | Where-Object Name -in $Column
                    } else {
                        $columns = $tableobject.Columns
                    }

                    if ($ExcludeColumn) {
                        $columns = $columns | Where-Object Name -notin $ExcludeColumn
                    }

                    # Loop through the columns
                    foreach ($columnobject in $columns) {
                        $candidateFound = $false

                        if ($columnobject.DataType.Name -eq "geography") {
                            if ($null -eq ($results | Where-Object { $_.Database -eq $dbName -and $_.Schema -eq $tableobject.Schema -and $_.Table -eq $tableobject.Name -and $_.Column -eq $columnobject.Name })) {
                                # Add the results
                                [pscustomobject]@{
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

                                $candidateFound = $true

                            }
                        } else {
                            if ($knownNames.Count -ge 1) {
                                # Check if the results not already contain a similar object
                                #if ($null -eq ($results | Where-Object { $_.Database -eq $dbName -and $_.Schema -eq $tableobject.Schema -and $_.Table -eq $tableobject.Name -and $_.Column -eq $columnobject.Name })) {
                                if (-not $candidateFound) {
                                    # Go through the first check to see if any column is found with a known type
                                    foreach ($knownName in $knownNames) {
                                        foreach ($pattern in $knownName.Pattern) {
                                            if (-not $candidateFound -and $columnobject.Name -match $pattern) {
                                                # Add the results
                                                [pscustomobject]@{
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
                                                }

                                                $candidateFound = $true
                                            }
                                        }
                                    }

                                    $knownName = $null
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on"
                            }

                            if ($patterns.Count -ge 1) {
                                # Check if the results not already contain a similar object
                                #if ($null -eq ($results | Where-Object { $_.Database -eq $dbName -and $_.Schema -eq $tableobject.Schema -and $_.Table -eq $tableobject.Name -and $_.Column -eq $columnobject.Name })) {
                                if (-not $candidateFound) {
                                    # Setup the query
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                                    # Get the data
                                    $dataset = @()

                                    try {
                                        $dataset += Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $dbName -Query $query -EnableException
                                    } catch {
                                        $errormessage = $_.Exception.Message.ToString()
                                        Stop-Function -Message "Error executing query $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $updatequery -Continue -ErrorRecord $_
                                    }

                                    # Check if there is any data
                                    if ($dataset.Count -ge 1) {

                                        # Loop through the patterns
                                        foreach ($patternobject in $patterns) {

                                            # If there is a result from the match
                                            if (-not $candidateFound -and $dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                                # Add the results
                                                [pscustomobject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                }

                                                $candidateFound = $true
                                            }

                                            $patternobject = $null
                                        }
                                    } else {
                                        Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on"
                            }
                        }
                    }

                    $tableNumber++

                } # End for each table
            } # End for each database
        } # End for each instance
    } # End process
}