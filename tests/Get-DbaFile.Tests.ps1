$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaFile).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FileType', 'Depth', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Returns some files" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $db = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $db")
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        $results = Get-DbaFile -SqlInstance $script:instance2
        It "Should find the new database file" {
            ($results.Filename -match 'dbatoolsci').Count -gt 0 | Should Be $true
        }

        $results = Get-DbaFile -SqlInstance $script:instance2 -Path (Get-DbaDefaultPath -SqlInstance $script:instance2).Log
        It "Should find the new database log file" {
            ($results.Filename -like '*dbatoolsci*ldf').Count -gt 0 | Should Be $true
        }

        $masterpath = $server.MasterDBPath
        $results = Get-DbaFile -SqlInstance $script:instance2 -Path $masterpath
        It "Should find the master database file" {
            $results.Filename -match 'master.mdf' | Should Be $true
        }
    }
}