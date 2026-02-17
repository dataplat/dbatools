#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbccDropCleanBuffer",
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
                "NoInformationalMessages",
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
            "Cmd",
            "Output"
        )
        $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $p = $result.PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }
    }

    Context "Works correctly" {
        It "returns results" {
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -Be $true
        }

        It "returns the right results for -NoInformationalMessages" {
            $noInfoResult = Invoke-DbaDbccDropCleanBuffer -SqlInstance $TestConfig.InstanceSingle -NoInformationalMessages
            $noInfoResult.Cmd -match "DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS" | Should -Be $true
            $noInfoResult.Output -eq $null | Should -Be $true
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
                "Cmd",
                "Output"
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