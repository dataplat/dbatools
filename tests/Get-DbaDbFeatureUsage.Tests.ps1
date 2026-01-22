#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFeatureUsage",
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
                "ExcludeDatabase",
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

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("Create Database [$dbname]")
        $server.Query("Create Table [$dbname].dbo.TestCompression
            (Column1 nvarchar(10),
            Column2 int PRIMARY KEY,
            Column3 nvarchar(18));")
        $server.Query("ALTER TABLE [$dbname].dbo.TestCompression REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("DROP Database [$dbname]")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Feature Usage" {
        It "Gets results" {
            $results = Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets Feature Usage using -Database" {
        BeforeAll {
            $results = Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Has the Feature Compression" {
            $results.Feature | Should -Be "Compression"
        }
    }

    Context "Gets Feature Usage using -ExcludeDatabase" {
        It "Gets results" {
            $results = Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname
            $results.database | Should -Not -Contain $dbname
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbFeatureUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Feature",
                "Database"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }
    }
}