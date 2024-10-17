param($ModuleName = 'dbatools')

Describe "Measure-DbaBackupThroughput" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Measure-DbaBackupThroughput
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have Since parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime -Not -Mandatory
        }
        It "Should have Last parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type Switch -Not -Mandatory
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have DeviceType parameter" {
            $CommandUnderTest | Should -HaveParameter DeviceType -Type String[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Returns output for single database" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance2 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $random = Get-Random
            $db = "dbatoolsci_measurethruput$random"
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Database $db | Backup-DbaDatabase
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $db
        }

        It "Should return results" {
            $results = Measure-DbaBackupThroughput -SqlInstance $global:instance2 -Database $db
            $results.Database | Should -Be $db
            $results.BackupCount | Should -Be 1
        }
    }
}
