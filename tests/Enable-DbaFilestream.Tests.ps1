#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaFilestream",
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
                "Credential",
                "FileStreamLevel",
                "ShareName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Disable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing FileStream Level" {
        It "Should change the FileStream Level to 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force

            $results.InstanceAccessLevel | Should -Be 1
            $results.ServiceAccessLevel | Should -Be 1
        }

        It "Should change the FileStream Level to 2" -Skip:$env:APPVEYOR {
            # Skip this test on AppVeyor because the instance does not support FileStream Level 2.
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 2 -ShareName TestShare -Force

            $results.InstanceAccessLevel | Should -Be 2
            $results.ServiceAccessLevel | Should -Be 2
            $results.ServiceShareName | Should -Be TestShare
        }

        It "Should warn if using ShareName with FileStreamLevel 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -ShareName Test -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike '*Filestream must be at least level 2 when using ShareName*'
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'InstanceAccess',
                'ServiceAccess',
                'ServiceShareName'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available" {
            $result.PSObject.Properties.Name | Should -Contain 'InstanceAccessLevel'
            $result.PSObject.Properties.Name | Should -Contain 'ServiceAccessLevel'
        }
    }
}