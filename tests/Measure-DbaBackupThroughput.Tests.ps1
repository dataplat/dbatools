$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Since', 'Last', 'Type', 'DeviceType', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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