#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaKbUpdate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Name",
                "Simple",
                "Language",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # These tests query the Microsoft Update Catalog. If that site does not answer, every one of them
    # needs 100 seconds to time out and then fails for a reason that has nothing to do with dbatools.
    # So we probe the catalog once here and skip the tests if it does not answer. We only skip if it
    # is provably down - if it answers, the tests run as before and a real regression still fails them.
    #
    # We have to probe the search page and not the start page: on 2026-07-31 the start page answered
    # in one second while every search timed out, so a probe of the start page would not have helped.
    try {
        $splatCatalog = @{
            Uri             = "https://www.catalog.update.microsoft.com/Search.aspx?q=KB4057119"
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = "Stop"
        }
        $catalogReachable = (Invoke-WebRequest @splatCatalog).StatusCode -eq 200
    } catch {
        $catalogReachable = $false
    }

    Context "Querying the Microsoft Update Catalog" -Skip:(-not $catalogReachable) {
        It "successfully connects and parses link and title" {
            $results = Get-DbaKbUpdate -Name KB4057119
            $results.Link -match "download.windowsupdate.com"
            $results.Title -match "Cumulative Update"
            $results.KBLevel | Should -Be 4057119
        }

        It "test with the -Simple param" {
            $results = Get-DbaKbUpdate -Name KB4577194 -Simple
            $results.Link -match "download.windowsupdate.com"
            $results.Title -match "Cumulative Update"
            $results.KBLevel | Should -Be 4577194
        }

        # see https://github.com/dataplat/dbatools/issues/6745
        It "Calling script uses a variable named filter" {
            $filter = "SQLServer*-KB-*x64*.exe"

            $results = Get-DbaKbUpdate -Name KB4564903
            $results.KBLevel | Should -Be 4564903
            $results.Link -match "download.windowsupdate.com"
            $results.Title -match "Cumulative Update"
        }

        It "Call with multiple KBs" {
            $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 3) {
                Write-Message -Level Warning -Message "Retrying..."
                Start-Sleep -s 30
                $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903
            }

            $results.KBLevel | Should -Contain 4057119
            $results.KBLevel | Should -Contain 4577194
            $results.KBLevel | Should -Contain 4564903
        }

        It "Call without specific language" {
            $results = Get-DbaKbUpdate -Name KB5003279
            $results.KBLevel | Should -Be 5003279
            $results.Classification -match "Service Packs"
            $results.Link -match "-enu_"
        }

        It "Call with specific language" {
            $results = Get-DbaKbUpdate -Name KB5003279 -Language ja
            $results.KBLevel | Should -Be 5003279
            $results.Classification -match "Service Packs"
            $results.Link -match "-jpn_"
        }
    }
}