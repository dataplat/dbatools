#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMemoryUsage",
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
                "IncludeSystemDb",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
    }

    Context "Functionality" {
        It "Returns data" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb
            $result.Status.Count | Should -BeGreaterOrEqual 1
        }

        It "Accepts a list of databases" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -Database "ResourceDb" -IncludeSystemDb

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Be "ResourceDb"
        }

        It "Excludes databases" {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb -ExcludeDatabase "ResourceDb"

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Not -Contain "ResourceDb"
            $uniqueDbs | Should -Contain "master"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'PageType',
                'Size',
                'PercentUsed'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has PageCount property available via Select-Object" {
            $result[0].PSObject.Properties.Name | Should -Contain 'PageCount' -Because "PageCount should be accessible even though excluded from default view"
        }
    }
}