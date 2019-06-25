$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        Context "Validate parameters" {
            [object[]]$params = (Get-Command -Name $CommandName).Parameters.Keys
            $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'ReSeedValue', 'EnableException'

            It "Should contain our specific parameters" {
                ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
            }
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-SqlInstance -SqlInstance $script:instance2
        $random = Get-Random
        $tableName1 = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"

        $dbname = "dbatoolsci_getdbUsage$random"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName1 (Id int NOT NULL IDENTITY (125, 1), Value varchar(5))", $dbname)
        $null = $server.Query("CREATE TABLE $tableName2 (Id int NOT NULL IDENTITY (  5, 1), Value varchar(5))", $dbname)

        $null = $server.Query("INSERT $tableName1(Value) SELECT 1", $dbname)
        $null = $server.Query("INSERT $tableName2(Value) SELECT 2", $dbname)
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate standard output " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Table', 'Cmd', 'IdentityValue', 'ColumnValue', 'Output'
        $result = Set-DbaDbIdentity -SqlInstance $script:instance2 -Database $dbname -Table $tableName1, $tableName2 -Confirm:$false

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }

        It "returns results for each table" {
            $result.Count -eq 2 | Should Be $true
        }

        It "returns correct results" {
            $result[1].IdentityValue -eq 5 | Should Be $true
        }
    }

    Context "Reseed option returns correct results " {
        $result = Set-DbaDbIdentity -SqlInstance $script:instance2 -Database $dbname -Table $tableName2 -ReSeedValue 400 -Confirm:$false

        It "returns correct results" {
            $result.cmd -eq "DBCC CHECKIDENT('$tableName2', RESEED, 400)" | Should Be $true
            $result.IdentityValue -eq '5.' | Should Be $true
        }
    }
}