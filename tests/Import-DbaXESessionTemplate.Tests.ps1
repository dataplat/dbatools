#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaXESessionTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "Path",
                "Template",
                "TargetFilePath",
                "TargetFileMetadataPath",
                "EnableException",
                "StartUpState"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session "Overly Complex Queries" | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        It -Skip:$true "session imports with proper name and non-default target file location" {
            $result = Import-DbaXESessionTemplate -SqlInstance $TestConfig.instance2 -Template "Overly Complex Queries" -TargetFilePath "C:\temp"
            $result.Name | Should -Be "Overly Complex Queries"
            $result.TargetFile -match "C:\\temp" | Should -Be $true
        }
    }
}
