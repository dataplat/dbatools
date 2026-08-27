#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDataGenerator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "FilePath",
                "Locale",
                "CharacterString",
                "Table",
                "Column",
                "ExcludeTable",
                "ExcludeColumn",
                "MaxValue",
                "ExactLength",
                "ModulusFactor",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test the data generator, we need a database with a test table.

        # Set variables. They are available in all the It blocks.
        $generatorDb = "dbatoolsci_generator"
        $createTableSql = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [varchar](100) NULL
                ) ON [PRIMARY];"

        # Create the objects.
        New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $generatorDb
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query $createTableSql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "Starts with the right data" {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select * from people" | Should -Be $null
        }

        It "Returns the proper output" {
            $configFile = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Path $backupPath -Rows 10

            $results = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $configFile.FullName

            foreach ($result in $results) {
                $result.Rows | Should -Be 10
                $result.Database | Should -Contain $generatorDb
            }

        }
        It "Generates the data" {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select * from people" | Should -Not -Be $null
        }
    }

    Context "Config that names a Faker property that does not generate data" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A Bogus.Faker object exposes the data sets next to its locale name, its context dictionary, its
            # index counters and DateTimeReference. Those are not generators, and reflecting over them made the
            # command offer their string, dictionary and integer methods as if they were subtypes. So a config
            # naming one of them was either rejected for the wrong reason or handed on to Get-DbaRandomizedValue,
            # which then warned without naming the column. Both configs below name the column that is at fault.
            $configTemplate = @"
{
  "Name": "$generatorDb",
  "Type": "DataGenerationConfiguration",
  "Tables": [
    {
      "Name": "people",
      "Schema": "dbo",
      "Columns": [
        {
          "Name": "City",
          "ColumnType": "varchar",
          "CharacterString": null,
          "MinValue": null,
          "MaxValue": 100,
          "MaskingType": "__MASKINGTYPE__",
          "SubType": "__SUBTYPE__",
          "Identity": false,
          "ForeignKey": false,
          "Composite": false,
          "Nullable": true
        }
      ],
      "ResetIdentity": false,
      "TruncateTable": false,
      "HasUniqueIndex": false,
      "Rows": 1
    }
  ]
}
"@

            # Locale is a string property of the faker object, so it is not a valid masking type.
            $junkTypeConfigPath = "$backupPath\junkmaskingtype.json"
            Set-Content -Path $junkTypeConfigPath -Value $configTemplate.Replace("__MASKINGTYPE__", "Locale").Replace("__SUBTYPE__", "City")

            # ContainsKey is a method of the context dictionary, so it is not a valid subtype.
            $junkSubTypeConfigPath = "$backupPath\junksubtype.json"
            Set-Content -Path $junkSubTypeConfigPath -Value $configTemplate.Replace("__MASKINGTYPE__", "Address").Replace("__SUBTYPE__", "ContainsKey")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Rejects the masking type and names the column" {
            $results = @(Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $junkTypeConfigPath -WarningAction SilentlyContinue)
            ($WarnVar -join " ") | Should -BeLike "*Errors found testing the configuration file*"
            $results.Column | Should -Contain "City"
            ($results | Where-Object Column -eq "City").Error | Should -BeLike "*MaskingType is not valid*"
        }

        It "Rejects the masking sub type and names the column" {
            $results = @(Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $junkSubTypeConfigPath -WarningAction SilentlyContinue)
            ($WarnVar -join " ") | Should -BeLike "*Errors found testing the configuration file*"
            $results.Column | Should -Contain "City"
            ($results | Where-Object Column -eq "City").Error | Should -BeLike "*SubType is not valid*"
        }

        It "Stops before running an insert it cannot fill" {
            # The insert statement names every column of the table, so running it with a rejected column
            # would leave it with fewer values than columns and SQL Server answered with a syntax error.
            $null = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $junkTypeConfigPath -WarningAction SilentlyContinue
            ($WarnVar -join " ") | Should -Not -BeLike "*Incorrect syntax*"
        }
    }

    Context "Config that uses a subtype Bogus exposes as a property" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Get-DbaRandomizedValue reads Person subtypes as a property, not as a method, so DateOfBirth and
            # the other Person subtypes work there. The command used to build its list of supported subtypes
            # from the methods of the Bogus.Faker object, which meant it rejected a config that used one.
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "CREATE TABLE [dbo].[persondata]([BirthDate] [date] NOT NULL) ON [PRIMARY];"

            $personConfig = @"
{
  "Name": "$generatorDb",
  "Type": "DataGenerationConfiguration",
  "Tables": [
    {
      "Name": "persondata",
      "Schema": "dbo",
      "Columns": [
        {
          "Name": "BirthDate",
          "ColumnType": "date",
          "CharacterString": null,
          "MinValue": null,
          "MaxValue": null,
          "MaskingType": "Person",
          "SubType": "DateOfBirth",
          "Identity": false,
          "ForeignKey": false,
          "Composite": false,
          "Nullable": false
        }
      ],
      "ResetIdentity": false,
      "TruncateTable": false,
      "HasUniqueIndex": false,
      "Rows": 5
    }
  ]
}
"@
            $personConfigPath = "$backupPath\persondateofbirth.json"
            Set-Content -Path $personConfigPath -Value $personConfig

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $personResult = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $personConfigPath
            $personWarning = $WarnVar
            $personRows = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select BirthDate from dbo.persondata"
        }

        It "Accepts the config without a warning" {
            $personWarning | Should -BeNullOrEmpty
        }

        It "Reports the generated rows" {
            $personResult.Rows | Should -Be 5
        }

        It "Writes a date to every row" {
            $personRows.BirthDate.Count | Should -Be 5
            $personRows.BirthDate | Should -BeOfType DateTime
        }

        It "Writes the same dates under a culture that formats them differently" {
            # DateOfBirth is one of the subtypes Bogus exposes as a property, so it arrives as a DateTime
            # rather than as a preformatted string. Converting it with ToString() and no culture would build
            # a SQL literal in the process culture and swap day and month wherever that is not month first.
            $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture

            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object System.Globalization.CultureInfo("de-DE")

                $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "truncate table dbo.persondata"
                $null = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $personConfigPath
                $germanRows = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select BirthDate from dbo.persondata"
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
            }

            $germanRows.BirthDate.Count | Should -Be 5
        }
    }

    Context "Config for a column the generator cannot fill" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Random/Replace is a valid combination, but it needs a Format that a data generation
            # configuration has nowhere to put, so the generator has to reject it up front rather than call
            # Get-DbaRandomizedValue once per row and insert nothing.
            $needsFormatConfig = @"
{
  "Name": "$generatorDb",
  "Type": "DataGenerationConfiguration",
  "Tables": [
    {
      "Name": "people",
      "Schema": "dbo",
      "Columns": [
        {
          "Name": "City",
          "ColumnType": "varchar",
          "CharacterString": null,
          "MinValue": null,
          "MaxValue": 100,
          "MaskingType": "Random",
          "SubType": "Replace",
          "Identity": false,
          "ForeignKey": false,
          "Composite": false,
          "Nullable": true
        }
      ],
      "ResetIdentity": false,
      "TruncateTable": false,
      "HasUniqueIndex": false,
      "Rows": 1
    }
  ]
}
"@
            $needsFormatConfigPath = "$backupPath\needsformat.json"
            Set-Content -Path $needsFormatConfigPath -Value $needsFormatConfig

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Names the parameter the configuration cannot supply" {
            $results = @(Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $needsFormatConfigPath -WarningAction SilentlyContinue)
            ($WarnVar -join " ") | Should -BeLike "*Errors found testing the configuration file*"
            ($results | Where-Object Column -eq "City").Error | Should -BeLike "*needs a Format*"
        }
    }

    Context "Config for a table with a unique index" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The values for a unique index are generated before the insert statement is built, so the column
            # checks have to run before that. While they ran later, an unusable column was invoked anyway and
            # the failure came from inside the uniqueness loop instead of from the configuration check.
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "CREATE TABLE [dbo].[uniquepeople]([City] [varchar](100) NOT NULL);
                CREATE UNIQUE INDEX [ix_uniquepeople_city] ON [dbo].[uniquepeople]([City]);"

            $uniqueConfig = @"
{
  "Name": "$generatorDb",
  "Type": "DataGenerationConfiguration",
  "Tables": [
    {
      "Name": "uniquepeople",
      "Schema": "dbo",
      "Columns": [
        {
          "Name": "City",
          "ColumnType": "varchar",
          "CharacterString": null,
          "MinValue": null,
          "MaxValue": 100,
          "MaskingType": "Locale",
          "SubType": "City",
          "Identity": false,
          "ForeignKey": false,
          "Composite": false,
          "Nullable": false
        }
      ],
      "ResetIdentity": false,
      "TruncateTable": false,
      "HasUniqueIndex": true,
      "Rows": 2
    }
  ]
}
"@
            $uniqueConfigPath = "$backupPath\uniqueindex.json"
            Set-Content -Path $uniqueConfigPath -Value $uniqueConfig

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Rejects the column before generating unique values for it" {
            $results = @(Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $uniqueConfigPath -WarningAction SilentlyContinue)
            ($WarnVar -join " ") | Should -BeLike "*Errors found testing the configuration file*"
            ($results | Where-Object Column -eq "City").Error | Should -BeLike "*MaskingType is not valid*"
        }

        It "Leaves the table empty" {
            (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select count(*) as c from dbo.uniquepeople").c | Should -Be 0
        }
    }

    Context "Config for a table with a unique index and a valid column" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The generated unique values were never written to the rows: the insert read them with a row
            # index variable that was never assigned, and the list of unique index columns was only filled
            # after a collision. So every row got a fresh random value instead of its pre-generated unique
            # one, and nothing guarded the rows against violating the index.
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "CREATE TABLE [dbo].[uniquenumbers]([Nr] [int] NOT NULL);
                CREATE UNIQUE INDEX [ix_uniquenumbers_nr] ON [dbo].[uniquenumbers]([Nr]);"

            $uniqueNumbersConfig = @"
{
  "Name": "$generatorDb",
  "Type": "DataGenerationConfiguration",
  "Tables": [
    {
      "Name": "uniquenumbers",
      "Schema": "dbo",
      "Columns": [
        {
          "Name": "Nr",
          "ColumnType": "int",
          "CharacterString": null,
          "MinValue": 1,
          "MaxValue": 10,
          "MaskingType": "Random",
          "SubType": "Number",
          "Identity": false,
          "ForeignKey": false,
          "Composite": false,
          "Nullable": false
        }
      ],
      "ResetIdentity": false,
      "TruncateTable": false,
      "HasUniqueIndex": true,
      "Rows": 10
    }
  ]
}
"@
            $uniqueNumbersConfigPath = "$backupPath\uniquenumbers.json"
            Set-Content -Path $uniqueNumbersConfigPath -Value $uniqueNumbersConfig

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $uniqueNumbersResult = Invoke-DbaDbDataGenerator -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -FilePath $uniqueNumbersConfigPath
            $uniqueNumbersWarning = $WarnVar
            $uniqueNumbersRows = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $generatorDb -Query "select Nr from dbo.uniquenumbers"
        }

        It "Accepts the config without a warning" {
            $uniqueNumbersWarning | Should -BeNullOrEmpty
        }

        It "Reports the generated rows" {
            $uniqueNumbersResult.Rows | Should -Be 10
        }

        It "Inserts every row with its own unique value" {
            # Ten rows from a domain of only ten values: without the unique value machinery, ten
            # independent random draws practically never form a permutation, so this fails when the
            # generated unique values are not the ones that reach the insert.
            $uniqueNumbersRows.Nr.Count | Should -Be 10
            ($uniqueNumbersRows.Nr | Select-Object -Unique).Count | Should -Be 10
        }
    }
}