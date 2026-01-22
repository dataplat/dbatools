#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfAvailableCounter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.InstanceSingle

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle
            $results.Count -gt 1000 | Should -Be $true
        }

        It "returns are pipable into Add-DbaPfDataCollectorCounter" {
            $results = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle -Pattern "*sql*" | Select-Object -First 3 | Add-DbaPfDataCollectorCounter -CollectorSet "Long Running Queries" -Collector "DataCollector01" -WarningAction SilentlyContinue
            foreach ($result in $results) {
                $result.Name -match "sql" | Should -Be $true
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "Name"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Credential property available via Select-Object" {
            $fullResult = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle -EnableException | Select-Object -First 1 -Property *
            $fullResult.PSObject.Properties.Name | Should -Contain "Credential"
        }
    }
}