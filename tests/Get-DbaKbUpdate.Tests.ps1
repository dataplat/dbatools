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
                "TimeoutSec",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    # The timeout only shows up in the call to Invoke-WebRequest, so there is nothing an integration
    # test could assert without an unreachable host. We mock inside the module - a mock without
    # -ModuleName never applies to the code under test and would silently test nothing.
    Context "Passing the timeout to the web request" {
        BeforeAll {
            Mock -CommandName Invoke-WebRequest -ModuleName dbatools -MockWith { }
        }

        It "Uses 30 seconds when TimeoutSec is not specified" {
            $null = Get-DbaKbUpdate -Name KB4057119 -WarningAction SilentlyContinue
            $splatShouldInvoke = @{
                CommandName     = "Invoke-WebRequest"
                ModuleName      = "dbatools"
                ParameterFilter = { $TimeoutSec -eq 30 }
            }
            Should -Invoke @splatShouldInvoke
        }

        It "Uses the value of TimeoutSec when it is specified" {
            $null = Get-DbaKbUpdate -Name KB4057119 -TimeoutSec 7 -WarningAction SilentlyContinue
            $splatShouldInvoke = @{
                CommandName     = "Invoke-WebRequest"
                ModuleName      = "dbatools"
                ParameterFilter = { $TimeoutSec -eq 7 }
            }
            Should -Invoke @splatShouldInvoke
        }

        It "Rejects a timeout of zero" {
            { Get-DbaKbUpdate -Name KB4057119 -TimeoutSec 0 } | Should -Throw -ExpectedMessage "*minimum allowed range*"
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
    # And we have to probe for a download button and not for the status code: on 2026-08-01 the search
    # page answered 200 in about a second but rendered no results table for any query, so a probe of
    # the status code let the tests run and fail. The download button is what the command itself looks
    # for, so this probe is true exactly when the command can work.
    # The same probe is used in Save-DbaKbUpdate.Tests.ps1.
    try {
        $splatCatalog = @{
            Uri             = "https://www.catalog.update.microsoft.com/Search.aspx?q=KB4057119"
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = "Stop"
        }
        $catalogResponse = Invoke-WebRequest @splatCatalog
        $catalogReachable = [bool]($catalogResponse.InputFields | Where-Object { $PSItem.type -eq "Button" -and $PSItem.class -eq "flatBlueButtonDownload focus-only" })
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