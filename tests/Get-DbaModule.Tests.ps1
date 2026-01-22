#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaModule",
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
                "ModifiedSince",
                "Type",
                "ExcludeSystemDatabases",
                "ExcludeSystemObjects",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Modules are properly retrieved" {
        BeforeAll {
            # SQL2008R2SP2 will return a number of modules from the msdb database so it is a good candidate to test
            $resultsTyped = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle -Type View -Database msdb
        }

        # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
        It "Should have a high count" {
            $results = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle | Select-Object -First 101
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have one type of object" {
            ($resultsTyped | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database" {
            ($resultsTyped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Accepts Piped Input" {
        BeforeAll {
            $dbMultiple = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb, master
            # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
            $resultsPiped = $dbMultiple | Get-DbaModule

            $dbSingle = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb
            $resultsPipedTyped = $dbSingle | Get-DbaModule -Type View
        }

        It "Should have a high count" {
            $resultsPiped.Count | Should -BeGreaterThan 100
        }

        It "Should only have two databases" {
            ($resultsPiped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 2
        }

        It "Should only have one type of object" {
            ($resultsPipedTyped | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database" {
            ($resultsPipedTyped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle -Database msdb -EnableException | Select-Object -First 1
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
                "Name",
                "ObjectID",
                "SchemaName",
                "Type",
                "CreateDate",
                "ModifyDate",
                "IsMsShipped",
                "ExecIsStartUp"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Definition property available via Select-Object *" {
            $fullResult = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle -Database msdb -EnableException | Select-Object -First 1 *
            $fullResult.PSObject.Properties.Name | Should -Contain "Definition" -Because "Definition should be available but hidden by default"
        }

        It "Does not show Definition property by default" {
            $result.PSObject.Properties.Name | Should -Not -Contain "Definition" -Because "Definition is excluded from default view"
        }
    }
}