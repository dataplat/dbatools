#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "UserName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        New-DbaCmConnection -ComputerName $env:COMPUTERNAME
    }

    AfterAll {
        Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME
    }

    Context "Returns DbaCmConnection" {
        It "Results are not Empty" {
            $cmConnectionResults = Get-DbaCmConnection -ComputerName $env:COMPUTERNAME
            $cmConnectionResults | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the expected type" {
            if (-not $cmConnectionResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $cmConnectionResults[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Connection.ManagementConnection"
        }

        It "Has the expected properties" {
            if (-not $cmConnectionResults) { Set-ItResult -Skipped -Because "no result to validate" }
            $cmConnectionResults[0].psobject.Properties["ComputerName"] | Should -Not -BeNullOrEmpty
            $cmConnectionResults[0].psobject.Properties["DisabledConnectionTypes"] | Should -Not -BeNullOrEmpty
            $cmConnectionResults[0].psobject.Properties["OverrideExplicitCredential"] | Should -Not -BeNullOrEmpty
        }
    }

    Context "Returns DbaCmConnection for User" {
        It "Results are not Empty" {
            $userConnectionResults = Get-DbaCmConnection -ComputerName $env:COMPUTERNAME -UserName *
            $userConnectionResults | Should -Not -BeNullOrEmpty
        }
    }
}