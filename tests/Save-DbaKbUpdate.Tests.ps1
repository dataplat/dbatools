#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaKbUpdate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Name",
                "Path",
                "FilePath",
                "Architecture",
                "Language",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create unique temp path for this test run to avoid conflicts
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory -Force
    }

    AfterAll {
        # Clean up all downloaded files and temp directory
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
    }

    It "downloads a small update" {
        $results = Save-DbaKbUpdate -Name KB2992080 -Architecture All -Path $tempPath
        $results.Name -match "aspnet"
        $filesToRemove += $results.FullName
    }

    It "supports piping" {
        $results = Get-DbaKbUpdate -Name KB2992080 | Select-Object -First 1 | Save-DbaKbUpdate -Architecture All -Path $tempPath
        $results.Name -match "aspnet"
        $filesToRemove += $results.FullName
    }

    It "Download multiple updates" {
        $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path $tempPath

        # basic retry logic in case the first download didn't get all of the files
        if ($null -eq $results -or $results.Count -ne 2) {
            Write-Message -Level Warning -Message "Retrying..."
            if ($results.Count -gt 0) {
                $filesToRemove += $results.FullName
            }
            Start-Sleep -s 30
            $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path $tempPath
        }

        $results.Count | Should -Be 2
        $filesToRemove += $results.FullName

        # download multiple updates via piping
        $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path $tempPath

        # basic retry logic in case the first download didn't get all of the files
        if ($null -eq $results -or $results.Count -ne 2) {
            Write-Message -Level Warning -Message "Retrying..."
            if ($results.Count -gt 0) {
                $filesToRemove += $results.FullName
            }
            Start-Sleep -s 30
            $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path $tempPath
        }

        $results.Count | Should -Be 2
        $filesToRemove += $results.FullName
    }

    # see https://github.com/dataplat/dbatools/issues/6745
    It "Ensuring that variable scope doesn't impact the command negatively" {
        $filter = "SQLServer*-KB-*x64*.exe"

        $results = Save-DbaKbUpdate -Name KB4513696 -Architecture All -Path $tempPath
        $results.Count | Should -Be 1
        $filesToRemove += $results.FullName
    }

    Context "Output validation" {
        BeforeAll {
            $outputTempPath = "$($TestConfig.Temp)\$CommandName-output-$(Get-Random)"
            $null = New-Item -Path $outputTempPath -ItemType Directory -Force
            $result = Save-DbaKbUpdate -Name KB2992080 -Architecture All -Path $outputTempPath
        }

        AfterAll {
            Remove-Item -Path $outputTempPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Returns files that exist on disk" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].FullName | Should -Exist
        }

        It "Returns files with content" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Length | Should -BeGreaterThan 0
        }
    }
}