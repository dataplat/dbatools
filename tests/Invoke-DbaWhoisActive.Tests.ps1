$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Filter', 'FilterType', 'NotFilter', 'NotFilterType', 'ShowOwnSpid', 'ShowSystemSpids', 'ShowSleepingSpids', 'GetFullInnerText', 'GetPlans', 'GetOuterCommand', 'GetTransactionInfo', 'GetTaskInfo', 'GetLocks', 'GetAverageTime', 'GetAdditonalInfo', 'FindBlockLeaders', 'DeltaInterval', 'OutputColumnList', 'SortOrder', 'FormatOutput', 'DestinationTable', 'ReturnSchema', 'Schema', 'Help', 'As', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $testzippath = "$script:appveyorlabrepo\CommunitySoftware\sp_whoisactive-12.00.zip"
        $resultInstallMaster = Install-DbaWhoIsActive -SqlInstance $script:instance1 -LocalFile $testzippath -Database master -WarningVariable warnInstallMaster
        $resultInstallTempdb = Install-DbaWhoIsActive -SqlInstance $script:instance1 -LocalFile $testzippath -Database tempdb -WarningVariable warnInstallTempdb
    }
    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance1 -Database master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        Invoke-DbaQuery -SqlInstance $script:instance1 -Database tempdb -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
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
        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -Help -WarningVariable warn
        It "Should execute and not warn" {
            $warn | Should -BeNullOrEmpty
        }

        It "Should execute and return Help" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1
        It -Skip "Should execute with no parameters in default location" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -ShowSleepingSpids 2
        It "Should execute with ShowSleepingSpids" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -Database Tempdb
        It -Skip "Should execute with no parameters against alternate install location" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -ShowOwnSpid
        It "Should execute with ShowOwnSpid" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -ShowSystemSpids
        It "Should execute with ShowSystemSpids" {
            $results | Should Not Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -Database Tempdb -GetAverageTime
        It -Skip "Should execute with averagetime" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -GetOuterCommand -FindBlockLeaders
        It -Skip "Should execute with GetOuterCommand and FindBlockLeaders" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance1 -NotFilter 0 -NotFilterType Program
        It -Skip "Should execute with NotFilter and NotFilterType" {
            $results | Should Be $Null
        }
    }
}