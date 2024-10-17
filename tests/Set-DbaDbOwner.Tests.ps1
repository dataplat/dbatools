param($ModuleName = 'dbatools')

Describe "Set-DbaDbOwner Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbOwner
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have TargetLogin parameter" {
            $CommandUnderTest | Should -HaveParameter TargetLogin -Type String -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Set-DbaDbOwner Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $svr = Connect-DbaInstance -SqlInstance $global:instance1
        $owner = "dbatoolssci_owner_$(Get-Random)"
        $ownertwo = "dbatoolssci_owner2_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $owner -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $ownertwo -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $dbnametwo = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname -Owner sa
        $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbnametwo -Owner sa
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname, $dbnametwo -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $global:instance1 -Login $owner, $ownertwo -Confirm:$false
    }
    Context "Should set the database owner" {
        It "Sets the database owner on a specific database" {
            $results = Set-DbaDbOwner -SqlInstance $global:instance1 -Database $dbName -TargetLogin $owner
            $results.Owner | Should -Be $owner
        }
        It "Check it actually set the owner" {
            $svr.Databases[$dbname].refresh()
            $svr.Databases[$dbname].Owner | Should -Be $owner
        }
    }

    Context "Sets multiple database owners" {
        BeforeAll {
            $results = Set-DbaDbOwner -SqlInstance $global:instance1 -Database $dbName, $dbnametwo -TargetLogin $ownertwo
        }
        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should -Be $ownertwo
            }
        }
        It "Set 2 database owners" {
            $results.Count | Should -Be 2
        }
    }

    Context "Excludes databases" {
        BeforeAll {
            $svr.Databases[$dbName].refresh()
            $results = Set-DbaDbOwner -SqlInstance $global:instance1 -ExcludeDatabase $dbnametwo -TargetLogin $owner
        }
        It "Excludes specified database" {
            $results.Database | Should -Not -Contain $dbnametwo
        }
        It "Updates at least one database" {
            @($results).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context "Enables input from Get-DbaDatabase" {
        BeforeAll {
            $svr.Databases[$dbnametwo].refresh()
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbnametwo
            $results = Set-DbaDbOwner -InputObject $db -TargetLogin $owner
        }
        It "Includes specified database" {
            $results.Database | Should -Be $dbnametwo
        }
        It "Sets the database owner on databases" {
            $results.owner | Should -Be $owner
        }
    }

    Context "Sets database owner to sa" {
        BeforeAll {
            $results = Set-DbaDbOwner -SqlInstance $global:instance1
        }
        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should -Be 'sa'
            }
        }
        It "Updates at least one database" {
            @($results).Count | Should -BeGreaterOrEqual 1
        }
    }
}
