#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDiskSpace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Unit",
                "SqlCredential",
                "ExcludeDrive",
                "CheckFragmentation",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Disks are properly retrieved" {
        BeforeAll {
            $allResults = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
            $systemDrive = "$env:SystemDrive\"
            $systemDriveResults = $allResults | Where-Object Name -eq $systemDrive
        }

        It "Returns at least the system drive" {
            $allResults.Name -contains $systemDrive | Should -Be $true
        }

        It "Has valid BlockSize property" {
            $systemDriveResults.BlockSize -gt 0 | Should -Be $true
        }

        It "Has valid SizeInGB property" {
            $systemDriveResults.SizeInGB -gt 0 | Should -Be $true
        }
    }
}