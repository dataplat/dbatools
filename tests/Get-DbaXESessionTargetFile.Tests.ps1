#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESessionTargetFile",
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
                "Session",
                "Target",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Regression tests" {
        It "Should accept Session objects as InputObject (issue #9840)" {
            $command = Get-Command $CommandName
            $inputObjectParam = $command.Parameters["InputObject"]
            $inputObjectParam.ParameterType.Name | Should -Be "Object[]"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $session = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session "system_health"
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command functionality" {
        It "Should accept Session objects and return FileInfo objects" {
            $result = $session | Get-DbaXESessionTargetFile
            $result | Should -Not -BeNullOrEmpty
            $result[0].GetType().Name | Should -Be "FileInfo"
        }

        It "Should work with Get-DbaXESessionTarget pipeline (issue #9840)" {
            $result = $session | Get-DbaXESessionTarget | Get-DbaXESessionTargetFile
            $result | Should -Not -BeNullOrEmpty
            $result[0].GetType().Name | Should -Be "FileInfo"
        }

        It "Should return files with .xel extension" {
            $result = $session | Get-DbaXESessionTargetFile
            $result.Extension | Should -Contain ".xel"
        }
    }
}