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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String
        }
        It "Should have Filter as a parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type System.String
        }
        It "Should have FilterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilterType -Type System.String
        }
        It "Should have NotFilter as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotFilter -Type System.String
        }
        It "Should have NotFilterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotFilterType -Type System.String
        }
        It "Should have ShowOwnSpid as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ShowOwnSpid -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ShowSystemSpids as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ShowSystemSpids -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ShowSleepingSpids as a parameter" {
            $CommandUnderTest | Should -HaveParameter ShowSleepingSpids -Type System.Int32
        }
        It "Should have GetFullInnerText as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetFullInnerText -Type System.Management.Automation.SwitchParameter
        }
        It "Should have GetPlans as a parameter" {
            $CommandUnderTest | Should -HaveParameter GetPlans -Type System.Int32
        }
        It "Should have GetOuterCommand as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetOuterCommand -Type System.Management.Automation.SwitchParameter
        }
        It "Should have GetTransactionInfo as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetTransactionInfo -Type System.Management.Automation.SwitchParameter
        }
        It "Should have GetTaskInfo as a parameter" {
            $CommandUnderTest | Should -HaveParameter GetTaskInfo -Type System.Int32
        }
        It "Should have GetLocks as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetLocks -Type System.Management.Automation.SwitchParameter
        }
        It "Should have GetAverageTime as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetAverageTime -Type System.Management.Automation.SwitchParameter
        }
        It "Should have GetAdditonalInfo as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter GetAdditonalInfo -Type System.Management.Automation.SwitchParameter
        }
        It "Should have FindBlockLeaders as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter FindBlockLeaders -Type System.Management.Automation.SwitchParameter
        }
        It "Should have DeltaInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter DeltaInterval -Type System.Int32
        }
        It "Should have OutputColumnList as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputColumnList -Type System.String
        }
        It "Should have SortOrder as a parameter" {
            $CommandUnderTest | Should -HaveParameter SortOrder -Type System.String
        }
        It "Should have FormatOutput as a parameter" {
            $CommandUnderTest | Should -HaveParameter FormatOutput -Type System.Int32
        }
        It "Should have DestinationTable as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationTable -Type System.String
        }
        It "Should have ReturnSchema as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReturnSchema -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type System.String
        }
        It "Should have Help as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Help -Type System.Management.Automation.SwitchParameter
        }
        It "Should have As as a parameter" {
            $CommandUnderTest | Should -HaveParameter As -Type System.String
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
