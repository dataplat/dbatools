param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSchema" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSchema
        }
        
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Schema",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
