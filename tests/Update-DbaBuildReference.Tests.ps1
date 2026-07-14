#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaBuildReference",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "LocalFile",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Deterministic local-file update flow" {
        InModuleScope dbatools {
            BeforeEach {
                $script:testOriginal = "C:\mockmodule\bin\dbatools-buildref-index.json"
                $script:testDataRoot = Join-Path ([IO.Path]::GetTempPath()) ("dbatools-buildref-test-" + [guid]::NewGuid().ToString("N"))
                $null = [IO.Directory]::CreateDirectory($script:testDataRoot)
                $script:testWritable = Join-Path $script:testDataRoot "dbatools-buildref-index.json"
                $script:testLocal = "C:\incoming\dbatools-buildref-index.json"
                $script:testOutputMessage = $null

                Mock Resolve-Path { $script:testOriginal }
                Mock Get-DbatoolsConfigValue { $script:testDataRoot } -ParameterFilter { $Name -eq "Path.DbatoolsData" }
                Mock Copy-Item { }
                Mock Write-Message { $script:testOutputMessage = $Message }
            }

            AfterEach {
                if ($script:testDataRoot -and [IO.Directory]::Exists($script:testDataRoot)) {
                    [IO.Directory]::Delete($script:testDataRoot, $true)
                }
            }

            It "seeds a missing writable copy and writes a newer local index" {
                Mock Test-Path {
                    if ("$Path" -eq $script:testOriginal) { return $true }
                    if ("$Path" -eq $script:testWritable) { return $false }
                    $false
                }
                Mock Get-Content {
                    if ("$Path" -eq $script:testOriginal) { return '{"LastUpdated":"2024-01-01T00:00:00"}' }
                    if ("$Path" -eq $script:testLocal) { return '{"LastUpdated":"2025-01-01T00:00:00"}' }
                    throw "unexpected path $Path"
                }

                Update-DbaBuildReference -LocalFile $script:testLocal -EnableException

                Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {
                    "$Path" -eq $script:testOriginal -and "$Destination" -eq $script:testWritable -and $Force -and "$ErrorAction" -eq "Stop"
                }
                [IO.File]::Exists($script:testWritable) | Should -BeTrue
                ([datetime]([IO.File]::ReadAllText($script:testWritable) | ConvertFrom-Json).LastUpdated).ToString("s") | Should -Be "2025-01-01T00:00:00"
                $script:testOutputMessage | Should -Be "Index updated correctly, last update on: 2025-01-01T00:00:00, was 2024-01-01T00:00:00"
            }

            It "keeps a newer writable index when the supplied local index is older" {
                Mock Test-Path {
                    if ("$Path" -eq $script:testOriginal -or "$Path" -eq $script:testWritable) { return $true }
                    $false
                }
                Mock Get-Content {
                    if ("$Path" -eq $script:testOriginal) { return '{"LastUpdated":"2024-01-01T00:00:00"}' }
                    if ("$Path" -eq $script:testWritable) { return '{"LastUpdated":"2026-01-01T00:00:00"}' }
                    if ("$Path" -eq $script:testLocal) { return '{"LastUpdated":"2025-01-01T00:00:00"}' }
                    throw "unexpected path $Path"
                }

                Update-DbaBuildReference -LocalFile $script:testLocal -EnableException

                Should -Invoke Copy-Item -Times 0 -Exactly
                [IO.File]::Exists($script:testWritable) | Should -BeFalse
                $script:testOutputMessage | Should -BeNullOrEmpty
            }
        }
    }
}
