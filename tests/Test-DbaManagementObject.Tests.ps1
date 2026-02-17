#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaManagementObject",
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
                "VersionNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $versionMajor = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor
    }

    Context "Command actually works" {
        BeforeAll {
            $trueResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber $versionMajor -OutVariable "global:dbatoolsciOutput"
            $falseResults = Test-DbaManagementObject -ComputerName $TestConfig.InstanceSingle -VersionNumber -1
        }

        It "Should have correct properties" {
            $expectedProps = @("ComputerName", "Version", "Exists")
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should -Be $true
        }

        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should -Be $false
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
                "Version",
                "Exists"
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