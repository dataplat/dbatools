param($ModuleName = 'dbatools')

Describe "New-DbaDbSchema" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbSchema
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Schema parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[]
        }
        It "Should have SchemaOwner parameter" {
            $CommandUnderTest | Should -HaveParameter SchemaOwner -Type String
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "New-DbaDbSchema Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $server1 = Connect-DbaInstance -SqlInstance $env:instance1
        $server2 = Connect-DbaInstance -SqlInstance $env:instance2
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        $userName = "user_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $logins = New-DbaLogin -SqlInstance $server1, $server2 -Login $userName -Password $securePassword -Force

        $null = New-DbaDbUser -SqlInstance $server1, $server2 -Database $newDbName -Login $userName
    }

    AfterAll {
        $null = $newDbs | Remove-DbaDatabase -Confirm:$false
        $null = $logins | Remove-DbaLogin -Confirm:$false
    }

    Context "commands work as expected" {
        It "validates required Schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1
            $schema | Should -BeNullOrEmpty
        }

        It "validates required Database param" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Schema TestSchema1
            $schema | Should -BeNullOrEmpty
        }

        It "creates a new schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be $userName
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            $schemas = New-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3 -SchemaOwner $userName
            $schemas.Count | Should -Be 4
            $schemas.Owner | Should -Be $userName, $userName, $userName, $userName
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName
        }

        It "reports a warning that the schema already exists" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -SchemaOwner $userName
            $schema | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $schema = Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | New-DbaDbSchema -Schema TestSchema4
            $schema.Count | Should -Be 1
            $schema.Owner | Should -Be dbo
            $schema.Name | Should -Be TestSchema4
            $schema.Parent.Name | Should -Be $newDbName
        }
    }
}
