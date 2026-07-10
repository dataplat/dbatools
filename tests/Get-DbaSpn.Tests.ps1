#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "AccountName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When listing SQL Server SPNs for a computer" {
        BeforeAll {
            $results = @(Get-DbaSpn -ComputerName $TestConfig.InstanceSingle.Split("\")[0] -WarningVariable warn 3> $null)
        }

        It "Should run without warning" {
            $warn | Should -BeNullOrEmpty
        }

        It "Should return at least one MSSQLSvc SPN" {
            $results.Count | Should -BeGreaterThan 0
        }

        It "Should have the expected properties" {
            $expectedProps = @("Input", "AccountName", "ServiceClass", "Port", "SPN")
            foreach ($result in $results) {
                ($result.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedProps | Sort-Object)
                $result.ServiceClass | Should -BeExactly "MSSQLSvc"
                $result.SPN | Should -Match "^MSSQLSvc/"
            }
        }
    }
}
