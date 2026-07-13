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
    Context "When relogging a captured blg" {
        BeforeAll {
            # a real 3-second logman capture gives relog.exe a genuine input file
            $blgDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $blgDir -ItemType Directory
            $counterPath = "\Processor(_Total)\% Processor Time"
            $null = logman create counter dbatoolsci_w1109 -c $counterPath -si 1 -o "$blgDir\dbatoolsci_w1109" -f bin
            $null = logman start dbatoolsci_w1109
            Start-Sleep -Seconds 3
            $null = logman stop dbatoolsci_w1109
            $null = logman delete dbatoolsci_w1109
        }

        AfterAll {
            $null = logman stop dbatoolsci_w1109 2>&1
            $null = logman delete dbatoolsci_w1109 2>&1
            Remove-Item -Path $blgDir -Recurse -ErrorAction SilentlyContinue
        }

        It "Converts a blg to csv and decorates the output file" {
            $blg = @(Get-ChildItem -Path $blgDir -Filter *.blg)
            $blg | Should -Not -BeNullOrEmpty
            $results = @(Invoke-DbaPfRelog -Path $blg[0].FullName -Type csv -AllowClobber)
            $results | Should -Not -BeNullOrEmpty
            $results[0].Extension | Should -Be ".csv"
            $results[0].RelogFile | Should -Be $true
        }
    }
}