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

    Context "Implementation regression" {
        It "passes ErrorAction Stop to Start-BitsTransfer so fallback errors are catchable" {
            $commandText = (Get-Command $CommandName).ScriptBlock.ToString()
            $bitsTransferCall = "Start-BitsTransfer -Source " + [char]36 + "link -Destination " + [char]36 + "file -ErrorAction Stop"

            $commandText | Should -Match ([regex]::Escape($bitsTransferCall))
        }

        It "checks UseWebRequest before selecting the BITS download path" {
            $commandText = (Get-Command $CommandName).ScriptBlock.ToString()
            $bitsTransferCondition = "if (-not " + [char]36 + "UseWebRequest -and (Get-Command Start-BitsTransfer -ErrorAction Ignore))"
            $webRequestCall = "Invoke-TlsWebRequest -Uri " + [char]36 + "link -OutFile " + [char]36 + "file -ErrorAction Stop"

            $commandText | Should -Match ([regex]::Escape($bitsTransferCondition))
            ([regex]::Matches($commandText, [regex]::Escape($webRequestCall))).Count | Should -Be 2
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Save-DbaKbUpdate resolves the KB through Get-DbaKbUpdate, so these tests query the Microsoft
    # Update Catalog as well. If that site does not answer, every one of them needs 100 seconds to
    # time out and then fails for a reason that has nothing to do with dbatools. So we probe the
    # catalog once here and skip the tests if it does not answer. We only skip if it is provably
    # down - if it answers, the tests run as before and a real regression still fails them.
    #
    # We have to probe the search page and not the start page: on 2026-07-31 the start page answered
    # in one second while every search timed out, so a probe of the start page would not have helped.
    # The same probe is used in Get-DbaKbUpdate.Tests.ps1.
    try {
        $splatCatalog = @{
            Uri             = "https://www.catalog.update.microsoft.com/Search.aspx?q=KB2992080"
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = "Stop"
        }
        $catalogReachable = (Invoke-WebRequest @splatCatalog).StatusCode -eq 200
    } catch {
        $catalogReachable = $false
    }

    BeforeAll {
        # Create unique temp path for this test run to avoid conflicts
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory -Force
    }

    AfterAll {
        # Clean up all downloaded files and temp directory
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "Downloading from the Microsoft Update Catalog" -Skip:(-not $catalogReachable) {
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
}