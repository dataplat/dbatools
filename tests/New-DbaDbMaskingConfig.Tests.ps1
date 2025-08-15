#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbMaskingConfig",
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
                "Table",
                "Column",
                "Path",
                "Locale",
                "CharacterString",
                "SampleCount",
                "KnownNameFilePath",
                "PatternFilePath",
                "ExcludeDefaultKnownName",
                "ExcludeDefaultPattern",
                "Force",
                "InputObject",
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

        # For all the files that we want to clean up after the test, we create a list that we can iterate over at the end.
        $filesToRemove = @()

        $maskingDbName = "dbatoolsci_maskconfig"
        $createPeopleTableSql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL
                ) ON [PRIMARY]"
        $testDatabase = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $maskingDbName
        $testDatabase.Query($createPeopleTableSql)
        $insertPeopleDataSql = "INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')"
        $testDatabase.Query($insertPeopleDataSql)

        # bug 6934
        $testDatabase.Query("
                CREATE TABLE dbo.DbConfigTest
                (
                    id              SMALLINT      NOT NULL,
                    IPAddress       VARCHAR(100)  NOT NULL,
                    Address         VARCHAR(100)  NOT NULL,
                    StreetAddress   VARCHAR(100)  NOT NULL,
                    Street          VARCHAR(100)  NOT NULL
                );
                INSERT INTO dbo.DbConfigTest (id, IPAddress, Address, StreetAddress, Street)
                VALUES
                (1, '127.0.0.1', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (2, '', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (3, 'fe80::7df3:7015:89e9:fbed%15', '123 Fake Street', '123 Fake Street', '123 Fake Street')")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $maskingDbName -Confirm:$false
        Remove-Item -Path $filesToRemove -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command works" {
        It "Should output a file with specific content" {
            $splatMaskingConfig = @{
                SqlInstance = $TestConfig.instance1
                                Database    = $maskingDbName
                                Path        = "C:\temp"
            }
            $configResults = New-DbaDbMaskingConfig @splatMaskingConfig
            $filesToRemove += $configResults.FullName

            $configResults.Directory.Name | Should -Be "temp"
            $configResults.FullName | Should -FileContentMatch $maskingDbName
            $configResults.FullName | Should -FileContentMatch "fname"
        }

        It "Bug 6934: matching IPAddress, Address, and StreetAddress on known names" {
            $splatMaskingConfig = @{
                SqlInstance = $TestConfig.instance1
                                Database    = $maskingDbName
                                Table       = "DbConfigTest"
                                Path        = "C:\temp"
            }
            $configResults = New-DbaDbMaskingConfig @splatMaskingConfig
            $filesToRemove += $configResults.FullName
            $jsonOutput = Get-Content $configResults.FullName | ConvertFrom-Json

            $jsonOutput.Tables.Columns[1].Name | Should -Be "IPAddress"
            $jsonOutput.Tables.Columns[1].MaskingType | Should -Be "Internet"
            $jsonOutput.Tables.Columns[1].SubType | Should -Be "Ip"

            $jsonOutput.Tables.Columns[2].Name | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[3].Name | Should -Be "StreetAddress"
            $jsonOutput.Tables.Columns[3].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[3].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[4].Name | Should -Be "Street"
            $jsonOutput.Tables.Columns[4].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[4].SubType | Should -Be "StreetAddress"
        }
    }
}