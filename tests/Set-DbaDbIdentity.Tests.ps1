param($ModuleName = 'dbatools')

Describe "Set-DbaDbIdentity" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbIdentity
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[]
        }
        It "Should have ReSeedValue as a parameter" {
            $CommandUnderTest | Should -HaveParameter ReSeedValue -Type Int32
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $env:instance2
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
            $null = Get-DbaDatabase -SqlInstance $env:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "Returns standard output with correct properties" {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Table', 'Cmd', 'IdentityValue', 'ColumnValue', 'Output'
            $result = Set-DbaDbIdentity -SqlInstance $env:instance2 -Database $dbname -Table $tableName1, $tableName2 -Confirm:$false

            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty
            }

            $result.Count | Should -Be 2
            $result[1].IdentityValue | Should -Be 5
        }

        It "Reseed option returns correct results" {
            $result = Set-DbaDbIdentity -SqlInstance $env:instance2 -Database $dbname -Table $tableName2 -ReSeedValue 400 -Confirm:$false

            $result.cmd | Should -Be "DBCC CHECKIDENT('$tableName2', RESEED, 400)"
            $result.IdentityValue | Should -Be '5.'
        }
    }
}
