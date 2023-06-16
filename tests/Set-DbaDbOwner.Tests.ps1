$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'TargetLogin', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $owner = "dbatoolssci_owner_$(Get-Random)"
        $ownertwo = "dbatoolssci_owner2_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $script:instance1 -Login $owner -Password ('Password1234!' | ConvertTo-SecureString -AsPlainText -Force)
        $null = New-DbaLogin -SqlInstance $script:instance1 -Login $ownertwo -Password ('Password1234!' | ConvertTo-SecureString -AsPlainText -Force)
        $dbName = "dbatoolsci_$(Get-Random)"
        $dbNameTwo = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbName -Owner sa
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbNameTwo -Owner sa
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbName, $dbNameTwo -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $script:instance1 -Login $owner, $ownertwo -Confirm:$false
    }
    Context "Should set the database owner" {
        It "Sets the database owner on a specific database" {
            $results = Set-DbaDbOwner -SqlInstance $script:instance1 -Database $dbName -TargetLogin $owner
            $results.Owner | Should -Be $owner
        }
        It "Check it actually set the owner" {
            (Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbName).Owner | Should -Be $owner
        }
    }
    Context "Sets multiple database owners" {
        $results = Set-DbaDbOwner -SqlInstance $script:instance1 -Database $dbName, $dbNameTwo -TargetLogin $ownertwo
        It "Sets the database owner on multiple databases" {
            ($results | Select-Object Owner -Unique).Count | Should -Be 1
        }
        It "Returns both database objects" {
            $results.Count | Should -Be 2
        }
    }
    Context "Excludes databases" {
        $results = Set-DbaDbOwner -SqlInstance $script:instance1 -ExcludeDatabase $dbNameTwo -TargetLogin $owner
        It "Excludes specified database" {
            $results.Database | Should Not Contain $dbNameTwo
        }
        It "Updates at least one database" {
            @($results).Count | Should BeGreaterOrEqual 1
        }
    }
    Context "Enables input from Get-DbaDatabase" {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbNameTwo
        $results = Set-DbaDbOwner -InputObject $db -TargetLogin $owner

        It "Includes specified database" {
            $results.Database | Should -Be $dbNameTwo
        }
        It "Sets the database owner on databases" {
            $results.owner | Should -Be $owner
        }
    }
    Context "Sets database owner to sa" {
        $results = Set-DbaDbOwner -SqlInstance $script:instance1 | Select-Object Owner -Unique
        It "Sets the database owner on multiple databases" {
            $results.Owner | Should -Be 'sa'
        }
        It "Updates at least one database" {
            @($results).Count | Should BeGreaterOrEqual 1
        }
    }
}