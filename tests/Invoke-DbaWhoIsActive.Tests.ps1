#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaWhoIsActive",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Filter",
                "FilterType",
                "NotFilter",
                "NotFilterType",
                "ShowOwnSpid",
                "ShowSystemSpids",
                "ShowSleepingSpids",
                "GetFullInnerText",
                "GetPlans",
                "GetOuterCommand",
                "GetTransactionInfo",
                "GetTaskInfo",
                "GetLocks",
                "GetAverageTime",
                "GetAdditonalInfo",
                "FindBlockLeaders",
                "DeltaInterval",
                "OutputColumnList",
                "SortOrder",
                "FormatOutput",
                "DestinationTable",
                "ReturnSchema",
                "Schema",
                "Help",
                "As",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testzippath = "$($TestConfig.appveyorlabrepo)\CommunitySoftware\sp_whoisactive-12.00.zip"
        $resultInstallMaster = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -LocalFile $testzippath -Database master -WarningVariable warnInstallMaster
        $resultInstallTempdb = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -LocalFile $testzippath -Database tempdb -WarningVariable warnInstallTempdb

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database master -Query "DROP PROCEDURE [dbo].[sp_WhoIsActive];" -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "DROP PROCEDURE [dbo].[sp_WhoIsActive];" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Should have SPWhoisActive installed correctly" {
        It "Should be installed to master" {
            $resultInstallMaster.Name | Should -Be "sp_WhoisActive"
            $warnInstallMaster | Should -BeNullOrEmpty
        }
        It "Should be installed to tempdb" {
            $resultInstallTempdb.Name | Should -Be "sp_WhoisActive"
            $warnInstallTempdb | Should -BeNullOrEmpty
        }
    }
    Context "Should Execute SPWhoisActive" {
        BeforeAll {
            $resultsHelp = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Help -WarningVariable warnHelp
            $resultsDefault = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1
            $resultsSleeping = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -ShowSleepingSpids 2
            $resultsTempdb = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database Tempdb
            $resultsOwnSpid = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -ShowOwnSpid
            $resultsSystemSpids = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -ShowSystemSpids
            $resultsAverageTime = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database Tempdb -GetAverageTime
            $resultsOuterCommand = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -GetOuterCommand -FindBlockLeaders
            $resultsNotFilter = Invoke-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -NotFilter 0 -NotFilterType Program
        }

        It "Should execute and not warn" {
            $warnHelp | Should -BeNullOrEmpty
        }

        It "Should execute and return Help" {
            $resultsHelp | Should -Not -BeNullOrEmpty
        }

        It -Skip:$true "Should execute with no parameters in default location" {
            $resultsDefault | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSleepingSpids" {
            $resultsSleeping | Should -Not -BeNullOrEmpty
        }

        It -Skip:$true "Should execute with no parameters against alternate install location" {
            $resultsTempdb | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowOwnSpid" {
            $resultsOwnSpid | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSystemSpids" {
            $resultsSystemSpids | Should -Not -BeNull
        }

        It -Skip:$true "Should execute with averagetime" {
            $resultsAverageTime | Should -BeNull
        }

        It -Skip:$true "Should execute with GetOuterCommand and FindBlockLeaders" {
            $resultsOuterCommand | Should -BeNull
        }

        It -Skip:$true "Should execute with NotFilter and NotFilterType" {
            $resultsNotFilter | Should -BeNull
        }
    }
}