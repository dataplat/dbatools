#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTable",
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
                "IncludeSystemDBs",
                "Table",
                "EnableException",
                "InputObject",
                "Schema"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $tablename = "dbatoolssci_$(Get-Random)"

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname -Owner sa
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "Create table $tablename (col1 int)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should get the table" {
        BeforeAll {
            $outputResult = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tablename
        }

        It "Gets the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
        }

        It "Gets the table when you specify the database" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Table"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedBaseDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex")
            foreach ($prop in $expectedBaseDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
            # FullTextIndex is always appended to the default display properties
            $defaultProps | Should -Contain "FullTextIndex" -Because "property 'FullTextIndex' should be in the default display set"
        }
    }

    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
        }
    }

}