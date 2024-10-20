param($ModuleName = 'dbatools')

Describe "Invoke-DbaWhoIsActive" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $testzippath = "$env:appveyorlabrepo\CommunitySoftware\sp_whoisactive-12.00.zip"
        $resultInstallMaster = Install-DbaWhoIsActive -SqlInstance $global:instance1 -LocalFile $testzippath -Database master -WarningVariable warnInstallMaster
        $resultInstallTempdb = Install-DbaWhoIsActive -SqlInstance $global:instance1 -LocalFile $testzippath -Database tempdb -WarningVariable warnInstallTempdb
    }

    AfterAll {
        Invoke-DbaQuery -SqlInstance $global:instance1 -Database master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        Invoke-DbaQuery -SqlInstance $global:instance1 -Database tempdb -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaWhoIsActive
        }
        $params = @(
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
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Should have SPWhoisActive installed correctly" {
        It "Should be installed to master" {
            $resultInstallMaster.Name | Should -Be 'sp_WhoisActive'
            $warnInstallMaster | Should -BeNullOrEmpty
        }
        It "Should be installed to tempdb" {
            $resultInstallTempdb.Name | Should -Be 'sp_WhoisActive'
            $warnInstallTempdb | Should -BeNullOrEmpty
        }
    }

    Context "Should Execute SPWhoisActive" {
        It "Should execute and return Help" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -Help -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSleepingSpids" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -ShowSleepingSpids 2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowOwnSpid" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -ShowOwnSpid
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSystemSpids" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -ShowSystemSpids
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with GetOuterCommand and FindBlockLeaders" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -GetOuterCommand -FindBlockLeaders
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with NotFilter and NotFilterType" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $global:instance1 -NotFilter 0 -NotFilterType Program
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
