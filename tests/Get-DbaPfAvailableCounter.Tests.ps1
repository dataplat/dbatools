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

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle | Select-Object -First 1
        }

        It "Returns output as PSCustomObject" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result.psobject.Properties.Name | Should -Contain "ComputerName"
            $result.psobject.Properties.Name | Should -Contain "Name"
        }

        It "Does not display Credential in default output" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Credential" -Because "Credential is excluded via Select-DefaultView -ExcludeProperty"
        }
    }
}