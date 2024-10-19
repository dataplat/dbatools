param($ModuleName = 'dbatools')

Describe "Remove-DbaDbRole Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbRole
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Role parameter" {
            $CommandUnderTest | Should -HaveParameter Role
        }
        It "Should have ExcludeRole parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeRole
        }
        It "Should have IncludeSystemDbs parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDbs
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Remove-DbaDbRole Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $role1 = "dbatoolssci_role1_$(Get-Random)"
        $role2 = "dbatoolssci_role2_$(Get-Random)"
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname1 -Owner sa
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname1 -Confirm:$false
    }

    Context "Functionality" {
        It 'Removes Non Fixed Roles' {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name | Should -Not -Contain $role1
            $result1.Name | Should -Not -Contain $role2
        }

        It 'Accepts a list of roles' {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $null = $server.Query("CREATE ROLE $role2", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1 -Role $role1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name | Should -Not -Contain $role1
            $result1.Name | Should -Contain $role2
        }

        It 'Excludes databases Roles' {
            $null = $server.Query("CREATE ROLE $role1", $dbname1)
            $result0 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1
            Remove-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1 -ExcludeRole $role1 -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name | Should -Contain $role1
            $result1.Name | Should -Not -Contain $role2
        }

        It 'Accepts input from Get-DbaDbRole' {
            $result0 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1 -Role $role2
            $result0 | Remove-DbaDbRole -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $global:instance2 -Database $dbname1

            $result1.Name | Should -Not -Contain $role2
        }

        It 'Removes roles in System DB' {
            $null = $server.Query("CREATE ROLE $role1", 'msdb')
            $result0 = Get-DbaDbRole -SqlInstance $global:instance2 -Database msdb
            Remove-DbaDbRole -SqlInstance $global:instance2 -Database msdb -Role $role1 -IncludeSystemDbs -Confirm:$false
            $result1 = Get-DbaDbRole -SqlInstance $global:instance2 -Database msdb

            $result0.Count | Should -BeGreaterThan $result1.Count
            $result1.Name | Should -Not -Contain $role1
        }
    }
}
