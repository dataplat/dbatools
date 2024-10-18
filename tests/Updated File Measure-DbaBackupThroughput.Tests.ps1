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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have Since parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type System.DateTime -Mandatory:$false
        }
        It "Should have Last parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String -Mandatory:$false
        }
        It "Should have DeviceType parameter" {
            $CommandUnderTest | Should -HaveParameter DeviceType -Type System.String[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
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
