$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 9
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Measure-DbaBackupThroughput).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Since', 'Last', 'Type', 'DeviceType', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Returns output for single database" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_measurethruput$random"
            $server.Query("CREATE DATABASE $db")
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Backup-DbaDatabase
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        $results = Measure-DbaBackupThroughput -SqlInstance $server -Database $db
        It "Should return just one backup" {
            $results.Database.Count -eq 1 | Should Be $true
        }
    }
}