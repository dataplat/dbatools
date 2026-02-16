#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccProcCache",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $props = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Count",
            "Used",
            "Active",
            "CacheSize",
            "CacheUsed",
            "CacheActive"
        )
        $result = Get-DbaDbccProcCache -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Command returns proper info" {
        It "Returns results for DBCC PROCCACHE" {
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Count",
                "Used",
                "Active",
                "CacheSize",
                "CacheUsed",
                "CacheActive"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}