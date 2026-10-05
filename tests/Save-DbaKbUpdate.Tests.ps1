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
    # And we have to probe for a download button and not for the status code: on 2026-08-01 the search
    # page answered 200 in about a second but rendered no results table for any query, so a probe of
    # the status code let the tests run and fail. The download button is what the command itself looks
    # for, so this probe is true exactly when the command can work.
    # The same probe is used in Get-DbaKbUpdate.Tests.ps1.
    try {
        $splatCatalog = @{
            Uri             = "https://www.catalog.update.microsoft.com/Search.aspx?q=KB2992080"
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = "Stop"
        }
        $catalogResponse = Invoke-WebRequest @splatCatalog
        $catalogReachable = [bool]($catalogResponse.InputFields | Where-Object { $PSItem.type -eq "Button" -and $PSItem.class -eq "flatBlueButtonDownload focus-only" })
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
            $results.Name | Should -Match "aspnet"
        }

        It "supports piping" {
            $results = Get-DbaKbUpdate -Name KB2992080 | Select-Object -First 1 | Save-DbaKbUpdate -Architecture All -Path $tempPath
            $results.Name | Should -Match "aspnet"
        }

        It "Download multiple updates" {
            $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path $tempPath

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 2) {
                Write-Message -Level Warning -Message "Retrying..."
                Start-Sleep -s 30
                $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path $tempPath
            }

            $results.Count | Should -Be 2

            # download multiple updates via piping
            $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path $tempPath

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 2) {
                Write-Message -Level Warning -Message "Retrying..."
                Start-Sleep -s 30
                $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path $tempPath
            }

            $results.Count | Should -Be 2
        }

        # see https://github.com/dataplat/dbatools/issues/6745
        It "Ensuring that variable scope doesn't impact the command negatively" {
            $filter = "SQLServer*-KB-*x64*.exe"

            $results = Save-DbaKbUpdate -Name KB4513696 -Architecture All -Path $tempPath
            $results.Count | Should -Be 1
        }
    }

    Context "When the download fails" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The link points to the top level domain
            # invalid, which never resolves, so the download fails; this needs neither the catalog nor the
            # internet. Invoke-WebRequest reports that as an error that ends only its own statement, so the
            # command would go on to its next line anyway; with -ErrorAction Stop of the caller the failure
            # throws out of the command, which is when the bar was left on screen. The runspace imports the
            # manifest: an import of the psm1 without a command line skips the type data.
            $failingUpdate = [PSCustomObject]@{
                Link = "https://progressleak$(Get-Random).invalid/sqlserver2022-kb0000000-x64_0000000000000000.exe"
            }
            $splatFailingDownload = @{
                InputObject   = $failingUpdate
                Path          = $tempPath
                UseWebRequest = $true
                ErrorAction   = "Stop"
            }
            $downloadRunspace = [runspacefactory]::CreateRunspace()
            $downloadRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $downloadRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $downloadShell = [powershell]::Create()
            $downloadShell.Runspace = $downloadRunspace
            $downloadError = $null
            try {
                $null = $downloadShell.AddCommand("Save-DbaKbUpdate").AddParameters($splatFailingDownload).Invoke()
            } catch {
                $downloadError = $PSItem
            }
            $downloadRecords = @($downloadShell.Streams.Progress)
            $downloadShell.Dispose()
            $downloadRunspace.Dispose()
        }

        It "Throws out of the failed download" {
            $downloadError | Should -Not -BeNullOrEmpty
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $downloadRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $downloadRecords | Where-Object Activity -like "Downloading *" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}