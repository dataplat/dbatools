$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbMasterKey).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = $server.Query("Create Database [$dbname]")
        $null = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database $dbname -Password (ConvertTo-SecureString -AsPlainText -Force -String 'ThisIsAPassword!') -Confirm:$false
    }
    AfterAll {
        Remove-DbaDbMasterKey -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    Context "Gets DbMasterKey" {
        $results = Get-DbaDbMasterKey -SqlInstance $script:instance1 | Where-Object {$_.Database -eq "$dbname"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be the key on $dbname" {
            $results.Database | Should Be $dbname
        }
        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should Be $true
        }
    }
    Context "Gets DbMasterKey when using -database" {
        $results = Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database $dbname
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be the key on $dbname" {
            $results.Database | Should Be $dbname
        }
        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should Be $true
        }
    }
    Context "Gets no DbMasterKey when using -ExcludeDatabase" {
        $results = Get-DbaDbMasterKey -SqlInstance $script:instance1 -ExcludeDatabase $dbname
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}