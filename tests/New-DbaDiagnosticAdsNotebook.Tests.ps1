#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDiagnosticAdsNotebook",
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
                "TargetVersion",
                "Path",
                "IncludeDatabaseSpecific",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testNotebookFile = "$($TestConfig.Temp)\myNotebook-$(Get-Random).ipynb"
    }

    AfterAll {
        $null = Remove-Item -Path $testNotebookFile -ErrorAction SilentlyContinue
    }

    Context "Creates notebook" {
        It "Should create a file" {
            $notebook = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $testNotebookFile -IncludeDatabaseSpecific -OutVariable "global:dbatoolsciOutput"
            $notebook | Should -Not -BeNullOrEmpty
        }

        It "Returns a file that includes specific phrases" {
            $results = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $testNotebookFile -IncludeDatabaseSpecific
            $results | Should -Not -BeNullOrEmpty
            ($results | Get-Content) -contains "information for current instance"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.IO\.FileInfo"
        }
    }
}