$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'TargetLogin', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $svr = Connect-DbaInstance -SqlInstance $script:instance1
        $owner = "dbatoolssci_owner_$(Get-Random)"
        $ownertwo = "dbatoolssci_owner2_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $script:instance1 -Login $owner -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $script:instance1 -Login $ownertwo -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $dbnametwo = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname -Owner sa
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbnametwo -Owner sa
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname, $dbnametwo -confirm:$false
        $null = Remove-DbaLogin -SqlInstance $script:instance1 -Login $owner, $ownertwo -confirm:$false
    }
    Context "Should set the database owner" {
        It "Sets the database owner on a specific database" {
            $results = Set-DbaDbOwner -SqlInstance $script:instance1 -Database $dbName -TargetLogin $owner
            $results.Owner | Should Be $owner
        }
        It "Check it actually set the owner" {
            $svr.Databases[$dbname].refresh()
            $svr.Databases[$dbname].Owner | Should Be $owner
        }
    }

    Context "Sets multiple database owners" {
        $results = Set-DbaDbOwner -SqlInstance $script:instance1 -Database $dbName, $dbnametwo -TargetLogin $ownertwo
        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should Be $ownertwo
            }
        }
        It "Set 2 database owners" {
            $results.Count | Should Be 2
        }
    }

    Context "Excludes databases" {
        $svr.Databases[$dbName].refresh()
        $results = Set-DbaDbOwner -SqlInstance $script:instance1 -ExcludeDatabase $dbnametwo -TargetLogin $owner
        It "Excludes specified database" {
            $results.Database | Should Not Contain $dbnametwo
        }
        It "Updates at least one database" {
            @($results).Count | Should BeGreaterOrEqual 1
        }
    }

    Context "Enables input from Get-DbaDatabase" {
        $svr.Databases[$dbnametwo].refresh()
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbnametwo
        $results = Set-DbaDbOwner -InputObject $db -TargetLogin $owner

        It "Includes specified database" {
            $results.Database | Should Be $dbnametwo
        }
        It "Sets the database owner on databases" {
            $results.owner | Should Be $owner
        }
    }

    Context "Sets database owner to sa" {
        $results = Set-DbaDbOwner -SqlInstance $script:instance1
        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should Be 'sa'
            }
        }
        It "Updates at least one database" {
            @($results).Count | Should BeGreaterOrEqual 1
        }
    }
}