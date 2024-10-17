param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSchema" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSchema
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Mandatory:$false
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[] -Mandatory:$false
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $random = Get-Random
            $server1 = Connect-DbaInstance -SqlInstance $global:instance1
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
            $newDbName = "dbatoolsci_newdb_$random"
            $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName
        }

        AfterAll {
            $null = $newDbs | Remove-DbaDatabase -Confirm:$false
        }

        Context "commands work as expected" {
            It "drops the schema" {
                $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1
                $schema.Count | Should -Be 1
                $schema.Name | Should -Be TestSchema1
                $schema.Parent.Name | Should -Be $newDbName

                Remove-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -Confirm:$false

                (Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1) | Should -BeNullOrEmpty

                $schemas = New-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3
                $schemas.Count | Should -Be 4
                $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
                $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName

                Remove-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3 -Confirm:$false

                (Get-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3) | Should -BeNullOrEmpty
            }

            It "supports piping databases" {
                $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1
                $schema.Count | Should -Be 1
                $schema.Name | Should -Be TestSchema1
                $schema.Parent.Name | Should -Be $newDbName

                Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | Remove-DbaDbSchema -Schema TestSchema1 -Confirm:$false

                (Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1) | Should -BeNullOrEmpty
            }
        }
    }
}
