#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDataMasking",
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
                "ModulusFactor",
                "ExactLength",
                "CommandTimeout",
                "BatchSize",
                "Retry",
                "DictionaryFilePath",
                "DictionaryExportPath",
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

        # Create unique temporary path for masking config files
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory

        $dbName = "dbatoolsci_masker"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL,
                    [percenttest] [decimal](15,3) NULL,
                    [bittest] bit NULL
                ) ON [PRIMARY]
                GO
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Joe','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Jane','Schmee','2/2/1950',65.38,0)
                GO
                CREATE TABLE [dbo].[people2](
                                    [fname] [varchar](50) NULL,
                                    [lname] [varchar](50) NULL,
                                    [dob] [datetime] NULL,
                                    [percenttest] [decimal](15,3) NULL,
                                    [bittest] bit NULL
                                ) ON [PRIMARY]
                GO
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Layla','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Eric','Schmee','2/2/1950',65.38,0)"

        $splatDatabase = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $dbName
        }
        $null = New-DbaDatabase @splatDatabase

        $splatQuery = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
            Query       = $sql
        }
        $null = Invoke-DbaQuery @splatQuery

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveDb = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
        }
        $null = Remove-DbaDatabase @splatRemoveDb -ErrorAction SilentlyContinue

        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command works" {
        It "starts with the right data" {
            $splatQuery1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where fname = 'Joe'"
            }
            Invoke-DbaQuery @splatQuery1 | Should -Not -Be $null

            $splatQuery2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuery2 | Should -Not -Be $null

            $splatQuery3 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 29.53"
            }
            Invoke-DbaQuery @splatQuery3 | Should -Not -Be $null

            $splatQuery4 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 65.38"
            }
            Invoke-DbaQuery @splatQuery4 | Should -Not -Be $null

            $splatQuery5 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 1 AND lname = 'Schmoe'"
            }
            Invoke-DbaQuery @splatQuery5 | Should -Not -Be $null

            $splatQuery6 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 0 AND lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuery6 | Should -Not -Be $null
        }

        It "returns the proper output" {
            $splatConfig = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Path        = $tempPath
            }
            $configFile = New-DbaDbMaskingConfig @splatConfig

            $splatMasking = @{
                FilePath    = $configFile.FullName
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
            }
            $results = @(Invoke-DbaDbDataMasking @splatMasking)

            $results[0].Rows | Should -Be 2
            $results[0].Database | Should -Contain $dbName

            $results[1].Rows | Should -Be 2
            $results[1].Database | Should -Contain $dbName
        }

        It "masks the data and does not delete it" {
            $splatQueryAll = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people"
            }
            Invoke-DbaQuery @splatQueryAll | Should -Not -Be $null

            $splatQueryJoe = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where fname = 'Joe'"
            }
            Invoke-DbaQuery @splatQueryJoe | Should -Be $null

            $splatQuerySchmee = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQuerySchmee | Should -Be $null

            $splatQueryPercent1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 29.53"
            }
            Invoke-DbaQuery @splatQueryPercent1 | Should -Be $null

            $splatQueryPercent2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where percenttest = 65.38"
            }
            Invoke-DbaQuery @splatQueryPercent2 | Should -Be $null

            $splatQueryBit1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 1 AND lname = 'Schmoe'"
            }
            Invoke-DbaQuery @splatQueryBit1 | Should -Be $null

            $splatQueryBit2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "select * from people where bittest = 0 AND lname = 'Schmee'"
            }
            Invoke-DbaQuery @splatQueryBit2 | Should -Be $null
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $splatConfig = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Path            = $tempPath
                EnableException = $true
            }
            $configFile = New-DbaDbMaskingConfig @splatConfig

            $splatMasking = @{
                FilePath        = $configFile.FullName
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                EnableException = $true
            }
            $result = @(Invoke-DbaDbDataMasking @splatMasking)
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "Table",
                "Columns",
                "Rows",
                "Elapsed",
                "Status"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }

        It "Returns one object per table processed" {
            $result.Count | Should -BeGreaterThan 0 -Because "at least one table should be processed"
        }

        It "Has Database property matching the target database" {
            $result[0].Database | Should -Be $dbName
        }

        It "Has Status property with valid values" {
            $result[0].Status | Should -BeIn @("Successful", "Failed")
        }

        It "Has Rows property as an integer" {
            $result[0].Rows | Should -BeOfType [int]
        }
    }
}