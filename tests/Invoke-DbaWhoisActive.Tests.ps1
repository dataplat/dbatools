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
        $null = Install-DbaWhoIsActive -SqlInstance $script:instance2 -LocalFile $testzippath -Database Master
        $null = Install-DbaWhoIsActive -SqlInstance $script:instance2 -LocalFile $testzippath -Database tempdb
    }
    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database Master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database Tempdb -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
    }
    Context "Should Execute SPWhoisActive" {
        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -Help
        It "Should execute and return Help" {
            $results | Should Not Be $null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2
        It "Should execute with no parameters in default location" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -ShowSleepingSpids 2
        It "Should execute with ShowSleepingSpids" {
            $results | Should -Not -BeNullOrEmpty
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -Database Tempdb
        It "Should execute with no parameters against alternate install location" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -ShowOwnSpid
        It "Should execute with ShowOwnSpid" {
            $results | Should Not Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -ShowSystemSpids
        It "Should execute with ShowSystemSpids" {
            $results | Should Not Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -Database Tempdb -GetAverageTime
        It "Should execute with averagetime" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -GetOuterCommand -FindBlockLeaders
        It "Should execute with GetOuterCommand and FindBlockLeaders" {
            $results | Should Be $Null
        }

        $results = Invoke-DbaWhoIsActive -SqlInstance $script:instance2 -NotFilter 0 -NotFilterType Program
        It "Should execute with NotFilter and NotFilterType" {
            $results | Should Be $Null
        }
    }
}