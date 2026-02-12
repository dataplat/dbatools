#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbCompatibility",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # No specific setup needed for this command
    }
    AfterAll {
        # No specific cleanup needed for this command
    }

    Context "Command actually works" {
        BeforeAll {
            $script:outputForValidation = Test-DbaDbCompatibility -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Should return a result" {
            $results = Test-DbaDbCompatibility -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDbCompatibility -Database Master -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result excluding one database" {
            $results = Test-DbaDbCompatibility -ExcludeDatabase Master -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }

        Context "Output validation" {
            It "Returns output of the expected type" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation[0] | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "ServerLevel", "Database", "DatabaseCompatibility", "IsEqual")
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }
        }
    }
}