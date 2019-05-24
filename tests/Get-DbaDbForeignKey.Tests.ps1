$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemTable', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"
        $fkName = "dbatools_getdbfk"
        $dbname = "dbatoolsci_getdbfk$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("CREATE TABLE $tableName (idTbl1 INT PRIMARY KEY)", $dbname)
        $server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT)", $dbname)
        $server.Query("ALTER TABLE $tableName2 ADD CONSTRAINT $fkName FOREIGN KEY (idTbl1) REFERENCES $tableName (idTbl1) ON UPDATE NO ACTION ON DELETE NO ACTION ", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        It "returns no foreign keys from excluded DB with -ExcludeDatabase" {
            $results = Get-DbaDbForeignKey -SqlInstance $script:instance2 -ExcludeDatabase master
            $results.where( {$_.Database -eq 'master'}).count | Should Be 0
        }
        It "returns only foreign keys from selected DB with -Database" {
            $results = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname
            $results.where( {$_.Database -ne 'master'}).count | Should Be 1
        }
        It "Should include test foreign keys: $ckName" {
            $results = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database $dbname -ExcludeSystemTable
            ($results | Where-Object Name -eq $ckName).Name | Should Be $ckName
        }
        It "Should exclude system tables" {
            $results = Get-DbaDbForeignKey -SqlInstance $script:instance2 -Database master -ExcludeSystemTable
            ($results | Where-Object Name -eq 'spt_fallback_db') | Should Be $null
        }
    }
}