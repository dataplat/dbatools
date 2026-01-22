#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Name",
                "Module",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving configuration values" {
        It "Should return a value that is an int" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout
            $results.Value | Should -BeOfType [int]
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbatoolsConfig -FullName sql.connection.timeout
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Configuration.ConfigurationValue]
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'Module',
                'Name',
                'Value',
                'Description',
                'Hidden'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }

    Context "Output with -Force" {
        BeforeAll {
            $resultWithForce = Get-DbatoolsConfig -Force
            $resultWithoutForce = Get-DbatoolsConfig
        }

        It "Returns more results when -Force is specified" {
            $resultWithForce.Count | Should -BeGreaterThan $resultWithoutForce.Count -Because "-Force should include hidden configuration values"
        }

        It "Includes hidden configuration values" {
            $hiddenConfigs = $resultWithForce | Where-Object { $_.Hidden -eq $true }
            $hiddenConfigs | Should -Not -BeNullOrEmpty -Because "-Force should reveal hidden configurations"
        }
    }
}