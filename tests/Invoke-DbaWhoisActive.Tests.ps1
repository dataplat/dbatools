param($ModuleName = 'dbatools')

Describe "Invoke-DbaWhoIsActive" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $testzippath = "$env:appveyorlabrepo\CommunitySoftware\sp_whoisactive-12.00.zip"
        $resultInstallMaster = Install-DbaWhoIsActive -SqlInstance $env:instance1 -LocalFile $testzippath -Database master -WarningVariable warnInstallMaster
        $resultInstallTempdb = Install-DbaWhoIsActive -SqlInstance $env:instance1 -LocalFile $testzippath -Database tempdb -WarningVariable warnInstallTempdb
    }

    AfterAll {
        Invoke-DbaQuery -SqlInstance $env:instance1 -Database master -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
        Invoke-DbaQuery -SqlInstance $env:instance1 -Database tempdb -Query 'DROP PROCEDURE [dbo].[sp_WhoIsActive];'
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaWhoIsActive
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Filter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String
        }
        It "Should have FilterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilterType -Type String
        }
        It "Should have NotFilter as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotFilter -Type String
        }
        It "Should have NotFilterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotFilterType -Type String
        }
        It "Should have ShowOwnSpid as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ShowOwnSpid -Type Switch
        }
        It "Should have ShowSystemSpids as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ShowSystemSpids -Type Switch
        }
        It "Should have ShowSleepingSpids as a parameter" {
            $CommandUnderTest | Should -HaveParameter ShowSleepingSpids -Type Int32
        }
        It "Should have GetFullInnerText as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetFullInnerText -Type Switch
        }
        It "Should have GetPlans as a parameter" {
            $CommandUnderTest | Should -HaveParameter GetPlans -Type Int32
        }
        It "Should have GetOuterCommand as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetOuterCommand -Type Switch
        }
        It "Should have GetTransactionInfo as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetTransactionInfo -Type Switch
        }
        It "Should have GetTaskInfo as a parameter" {
            $CommandUnderTest | Should -HaveParameter GetTaskInfo -Type Int32
        }
        It "Should have GetLocks as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetLocks -Type Switch
        }
        It "Should have GetAverageTime as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetAverageTime -Type Switch
        }
        It "Should have GetAdditonalInfo as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetAdditonalInfo -Type Switch
        }
        It "Should have FindBlockLeaders as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter FindBlockLeaders -Type Switch
        }
        It "Should have DeltaInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter DeltaInterval -Type Int32
        }
        It "Should have OutputColumnList as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputColumnList -Type String
        }
        It "Should have SortOrder as a parameter" {
            $CommandUnderTest | Should -HaveParameter SortOrder -Type String
        }
        It "Should have FormatOutput as a parameter" {
            $CommandUnderTest | Should -HaveParameter FormatOutput -Type Int32
        }
        It "Should have DestinationTable as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationTable -Type String
        }
        It "Should have ReturnSchema as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReturnSchema -Type Switch
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String
        }
        It "Should have Help as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Help -Type Switch
        }
        It "Should have As as a parameter" {
            $CommandUnderTest | Should -HaveParameter As -Type String
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -Help -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSleepingSpids" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -ShowSleepingSpids 2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowOwnSpid" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -ShowOwnSpid
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with ShowSystemSpids" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -ShowSystemSpids
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with GetOuterCommand and FindBlockLeaders" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -GetOuterCommand -FindBlockLeaders
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should execute with NotFilter and NotFilterType" {
            $results = Invoke-DbaWhoIsActive -SqlInstance $env:instance1 -NotFilter 0 -NotFilterType Program
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
