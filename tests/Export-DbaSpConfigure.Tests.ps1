#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSpConfigure",
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
                "Path",
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
#
#    Integration test should appear below and are custom to the command you are writing.
#    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
#    for more guidence.
#

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When exporting sp_configure settings" {
        It "Should export sp_configure to a sql file" {
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $backupPath -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Extension | Should -Be ".sql"
        }

        It "Should contain sp_configure statements" {
            $content = Get-Content -Path $global:dbatoolsciOutput[0].FullName -Raw
            $content | Should -Match "EXEC sp_configure"
        }

        It "Should export to a specific file path" {
            $filePath = "$backupPath\sp_configure_test.sql"
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $filePath
            $result | Should -Not -BeNullOrEmpty
            $result.FullName | Should -Be $filePath
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