param($ModuleName = 'dbatools')

Describe "Get-DbaDbCheckConstraint Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbCheckConstraint
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeSystemTable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemTable -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

Describe "Get-DbaDbCheckConstraint Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"
        $ckName = "dbatools_getdbck"
        $dbname = "dbatoolsci_getdbfk$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("CREATE TABLE $tableName (idTbl1 INT PRIMARY KEY)", $dbname)
        $server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT, id3 INT)", $dbname)
        $server.Query("ALTER TABLE $tableName2 ADD CONSTRAINT $ckName CHECK (id3 > 10)", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        It "returns no check constraints from excluded DB with -ExcludeDatabase" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $global:instance2 -ExcludeDatabase master
            $results.where( { $_.Database -eq 'master' }).count | Should -Be 0
        }
        It "returns only check constraints from selected DB with -Database" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $global:instance2 -Database $dbname
            $results.where( { $_.Database -ne 'master' }).count | Should -Be 1
            $results.DatabaseId | Get-Unique | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname).Id
        }
        It "Should include test check constraint: $ckName" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $global:instance2 -Database $dbname -ExcludeSystemTable
            ($results | Where-Object Name -eq $ckName).Name | Should -Be $ckName
        }
        It "Should exclude system tables" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $global:instance2 -Database master -ExcludeSystemTable
            ($results | Where-Object Name -eq 'spt_fallback_db') | Should -BeNullOrEmpty
        }
    }
}
