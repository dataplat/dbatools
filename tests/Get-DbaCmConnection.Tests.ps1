#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "UserName",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        New-DbaCmConnection -ComputerName $env:COMPUTERNAME
    }

    AfterAll {
        Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -Confirm:$false
    }

    Context "Returns DbaCmConnection" {
        BeforeAll {
            $cmConnectionResults = Get-DbaCmConnection -ComputerName $env:COMPUTERNAME
        }

        It "Results are not Empty" {
            $cmConnectionResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Returns DbaCmConnection for User" {
        BeforeAll {
            $userConnectionResults = Get-DbaCmConnection -ComputerName $env:COMPUTERNAME -UserName *
        }

        It "Results are not Empty" {
            $userConnectionResults | Should -Not -BeNullOrEmpty
        }
    }
}