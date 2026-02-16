#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccHelp",
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
                "Statement",
                "IncludeUndocumented",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $props = @("Operation", "Cmd", "Output")
        $result = Get-DbaDbccHelp -SqlInstance $TestConfig.InstanceSingle -Statement FREESYSTEMCACHE -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate standard output" {
        It "Should return property: Operation" {
            $result.PSObject.Properties["Operation"].Name | Should -Be "Operation"
        }

        It "Should return property: Cmd" {
            $result.PSObject.Properties["Cmd"].Name | Should -Be "Cmd"
        }

        It "Should return property: Output" {
            $result.PSObject.Properties["Output"].Name | Should -Be "Output"
        }
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $result.Operation | Should -Be "FREESYSTEMCACHE"
            $result.Cmd | Should -Be "DBCC HELP(FREESYSTEMCACHE)"
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "returns the right results for PAGE" {
            $pageResult = Get-DbaDbccHelp -SqlInstance $TestConfig.InstanceSingle -Statement PAGE -IncludeUndocumented
            $pageResult.Operation | Should -Be "PAGE"
            $pageResult.Cmd | Should -Be "DBCC HELP(PAGE)"
            $pageResult.Output | Should -Not -BeNullOrEmpty
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
                "Operation",
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