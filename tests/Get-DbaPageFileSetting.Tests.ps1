#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPageFileSetting",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:(-not $env:appveyor) {
    # Skip on local tests as we don't get any results on SQL Server 2022

    Context "Gets PageFile Settings" {
        It "Gets results" {
            $results = Get-DbaPageFileSetting -ComputerName $env:ComputerName
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (2026-07-06, Track A): pin the observed behavior of the live
    # implementation against the lab gate runner ahead of the C# port. The runner uses
    # automatic page file management, so the command emits exactly one summary object
    # with all file-specific fields null.
    Context "When the page file is automatically managed" {
        BeforeAll {
            $pageFileResults = @(Get-DbaPageFileSetting -ComputerName $env:ComputerName)
        }

        It "Returns exactly one PageFileSetting object" {
            $pageFileResults.Count | Should -Be 1
            $pageFileResults[0] | Should -BeOfType Dataplat.Dbatools.Computer.PageFileSetting
        }

        It "Reports automatic management with null file details" {
            $pageFileResults[0].ComputerName | Should -Be $env:ComputerName
            $pageFileResults[0].AutoPageFile | Should -BeTrue
            $pageFileResults[0].FileName | Should -BeNullOrEmpty
            $pageFileResults[0].SystemManaged | Should -BeNullOrEmpty
            $pageFileResults[0].AllocatedBaseSize | Should -BeNullOrEmpty
        }

        It "Accepts pipeline input" {
            $pipelineResults = @($env:ComputerName | Get-DbaPageFileSetting)
            $pipelineResults.Count | Should -Be 1
            $pipelineResults[0].AutoPageFile | Should -BeTrue
        }
    }
}