#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaReplServerSetting",
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
                "ScriptOption",
                "InputObject",
                "Encoding",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When the file exists and NoClobber is set" {
        BeforeAll {
            $existingFile = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_replsetting_$(Get-Random).sql"
            Set-Content -Path $existingFile -Value "dbatoolsci"
        }

        AfterAll {
            Remove-Item -Path $existingFile -Force -ErrorAction SilentlyContinue
        }

        It "Warns and leaves the file alone" {
            # -NoClobber was declared and documented but never checked, so an existing file was appended to (#10607).
            # The check runs before the replication settings are scripted, so no distributor is needed.
            $splatExport = @{
                SqlInstance   = $TestConfig.InstanceSingle
                FilePath      = $existingFile
                NoClobber     = $true
                WarningAction = "SilentlyContinue"
            }
            $null = Export-DbaReplServerSetting @splatExport
            ($WarnVar -join " ") | Should -BeLike "*already exists*"
            Get-Content -Path $existingFile | Should -Be "dbatoolsci"
        }
    }
}
