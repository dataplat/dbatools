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
            $results = Get-DbaPfAvailableCounter -ComputerName $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "Name",
                "Credential"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "Name"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}