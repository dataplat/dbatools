#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaPfRelog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Destination",
                "Type",
                "Append",
                "AllowClobber",
                "PerformanceCounter",
                "PerformanceCounterPath",
                "Interval",
                "BeginTime",
                "EndTime",
                "ConfigPath",
                "Summary",
                "InputObject",
                "Multithread",
                "AllTime",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempDir -ItemType Directory -Force

        # Create a .blg perfmon log file for testing
        $blgPath = "$tempDir\dbatoolsci_test.blg"
        $collectorName = "dbatoolsci_pfrelog_$(Get-Random)"
        $null = logman create counter $collectorName -c "\Processor(_Total)\% Processor Time" -si 1 -sc 3 -f bin -o "$tempDir\dbatoolsci_test" --v 2>&1
        $null = logman start $collectorName 2>&1
        Start-Sleep -Seconds 5
        $null = logman stop $collectorName 2>&1
        $null = logman delete $collectorName 2>&1

        # Find the generated .blg file
        $blgFile = Get-ChildItem -Path $tempDir -Filter "*.blg" -Recurse | Select-Object -First 1
        if ($blgFile) {
            $blgPath = $blgFile.FullName
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        Remove-Item -Path $tempDir -Recurse -ErrorAction SilentlyContinue
    }

    Context "When converting a .blg file to tsv" {
        BeforeAll {
            $splatRelog = @{
                Path          = $blgPath
                Destination   = "$tempDir\output_tsv"
                Type          = "tsv"
                AllowClobber  = $true
            }
            $results = Invoke-DbaPfRelog @splatRelog -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return a file object" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should create a .tsv file" {
            $results.Extension | Should -Be ".tsv"
        }

        It "Should have the RelogFile property set to true" {
            $results.RelogFile | Should -BeTrue
        }

        It "Should create a file with content" {
            $results.Length | Should -BeGreaterThan 0
        }
    }

    Context "When converting a .blg file to csv" {
        BeforeAll {
            $splatRelog = @{
                Path          = $blgPath
                Destination   = "$tempDir\output_csv"
                Type          = "csv"
                AllowClobber  = $true
            }
            $results = Invoke-DbaPfRelog @splatRelog
        }

        It "Should return a file object" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should create a .csv file" {
            $results.Extension | Should -Be ".csv"
        }

        It "Should have the RelogFile property set to true" {
            $results.RelogFile | Should -BeTrue
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have the RelogFile NoteProperty" {
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "RelogFile"
            $global:dbatoolsciOutput[0].RelogFile | Should -BeTrue
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.IO\.FileInfo"
        }
    }
}