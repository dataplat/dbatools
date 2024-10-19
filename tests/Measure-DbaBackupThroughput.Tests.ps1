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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Since",
                "Last",
                "Type",
                "DeviceType",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
