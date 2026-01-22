#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbFileGrowth",
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
                "GrowthType",
                "Growth",
                "FileType",
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

        # Create a test database for file growth operations
        $testDbName = "dbatoolsci_filegrowthtests"
        $splatNewDatabase = @{
            SqlInstance = $TestConfig.InstanceSingle
            Name        = $testDbName
        }
        $newdb = New-DbaDatabase @splatNewDatabase

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the test database
        $splatRemoveDatabase = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $testDbName
        }
        Remove-DbaDatabase @splatRemoveDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should return file information for only test database" {
        BeforeAll {
            $splatSetFileGrowth = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
            }
            $result = Set-DbaDbFileGrowth @splatSetFileGrowth | Select-Object -First 1
        }

        It "returns the proper info" {
            $result.Database | Should -Be $testDbName
            $result.GrowthType | Should -Be "kb"
        }
    }

    Context "Supports piping" {
        BeforeAll {
            $result = Get-DbaDatabase $TestConfig.InstanceSingle -Database $testDbName | Set-DbaDbFileGrowth | Select-Object -First 1
        }

        It "returns only test database files" {
            $result.Database | Should -Be $testDbName
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $splatSetFileGrowth = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $testDbName
                EnableException = $true
            }
            $result = Set-DbaDbFileGrowth @splatSetFileGrowth | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "MaxSize",
                "GrowthType",
                "Growth",
                "File",
                "FileName",
                "State"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}