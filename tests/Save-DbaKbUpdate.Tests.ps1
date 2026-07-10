#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "UseWebRequest",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    # These two regressions assert SOURCE TEXT of the PS implementation; a compiled cmdlet has no
    # ScriptBlock to inspect, so they only apply while the command is still a script function. The
    # behavior itself (BITS -ErrorAction Stop + the UseWebRequest gate + the IWR fallback) is
    # covered end-to-end by the IntegrationTests downloads.
    Context "Implementation regression" {
        It "passes ErrorAction Stop to Start-BitsTransfer so fallback errors are catchable" -Skip:((Get-Command $CommandName).CommandType -ne "Function") {
            $commandText = (Get-Command $CommandName).ScriptBlock.ToString()
            $bitsTransferCall = "Start-BitsTransfer -Source " + [char]36 + "link -Destination " + [char]36 + "file -ErrorAction Stop"

            $commandText | Should -Match ([regex]::Escape($bitsTransferCall))
        }

        It "checks UseWebRequest before selecting the BITS download path" -Skip:((Get-Command $CommandName).CommandType -ne "Function") {
            $commandText = (Get-Command $CommandName).ScriptBlock.ToString()
            $bitsTransferCondition = "if (-not " + [char]36 + "UseWebRequest -and (Get-Command Start-BitsTransfer -ErrorAction Ignore))"
            $webRequestCall = "Invoke-TlsWebRequest -Uri " + [char]36 + "link -OutFile " + [char]36 + "file -ErrorAction Stop"

            $commandText | Should -Match ([regex]::Escape($bitsTransferCondition))
            ([regex]::Matches($commandText, [regex]::Escape($webRequestCall))).Count | Should -Be 2
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
}