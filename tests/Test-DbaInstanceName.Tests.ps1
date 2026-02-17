#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaInstanceName",
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
                "ExcludeSsrs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command tests servername" {
        BeforeAll {
            $results = Test-DbaInstanceName -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
            # "-WarningAction SilentlyContinue" because on a cluster we get this warning:
            # "$instance is a cluster. Renaming clusters is not supported by Microsoft."
        }

        It "should say rename is not required" {
            $results.RenameRequired | Should -Be $false
        }

        It "returns the correct properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "ServerName", "NewServerName", "RenameRequired", "Updatable", "Warnings", "Blockers"
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
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
                "ServerName",
                "NewServerName",
                "RenameRequired",
                "Updatable",
                "Warnings",
                "Blockers"
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