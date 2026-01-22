#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "IncludeFilter",
                "ExcludeFilter",
                "Peek",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a temporary config file for testing
            $tempConfig = [System.IO.Path]::GetTempFileName()
            $configData = @{
                Version = 1
                Values  = @(
                    @{
                        FullName      = "test.import.setting1"
                        Value         = "TestValue1"
                        Type          = "System.String"
                        KeepPersisted = $false
                    }
                    @{
                        FullName      = "test.import.setting2"
                        Value         = 42
                        Type          = "System.Int32"
                        KeepPersisted = $true
                    }
                )
            }
            $configData | ConvertTo-Json -Depth 3 | Set-Content -Path $tempConfig
        }

        AfterAll {
            # Clean up temporary file
            if (Test-Path $tempConfig) {
                Remove-Item $tempConfig -Force
            }
        }

        Context "Output without -Peek" {
            It "Returns no output by default" {
                $result = Import-DbatoolsConfig -Path $tempConfig -EnableException
                $result | Should -BeNullOrEmpty
            }
        }

        Context "Output with -Peek" {
            BeforeAll {
                $result = Import-DbatoolsConfig -Path $tempConfig -Peek -EnableException
            }

            It "Returns configuration element objects" {
                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -BeGreaterThan 0
            }

            It "Has the expected properties" {
                $expectedProps = @(
                    'FullName',
                    'Value',
                    'Type',
                    'KeepPersisted'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present in peek output"
                }
            }

            It "Returns all unfiltered configuration items" {
                $result.Count | Should -Be 2
            }
        }

        Context "Output with -Peek and -IncludeFilter" {
            BeforeAll {
                $result = Import-DbatoolsConfig -Path $tempConfig -Peek -IncludeFilter "test.import.setting1" -EnableException
            }

            It "Returns only filtered configuration items" {
                $result.Count | Should -Be 1
                $result.FullName | Should -Be "test.import.setting1"
            }
        }

        Context "Output with -Peek and -ExcludeFilter" {
            BeforeAll {
                $result = Import-DbatoolsConfig -Path $tempConfig -Peek -ExcludeFilter "test.import.setting2" -EnableException
            }

            It "Excludes filtered configuration items" {
                $result.Count | Should -Be 1
                $result.FullName | Should -Be "test.import.setting1"
            }
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>