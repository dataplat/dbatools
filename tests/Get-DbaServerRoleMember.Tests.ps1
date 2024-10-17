param($ModuleName = 'dbatools')

Describe "Get-DbaServerRoleMember Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaServerRoleMember
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have ServerRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole -Type String[]
        }
        It "Should have ExcludeServerRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeServerRole -Type String[]
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type Object[]
        }
        It "Should have ExcludeFixedRole as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFixedRole -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Get-DbaServerRoleMember Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $server2 = Connect-DbaInstance -SqlInstance $script:instance2

        $password1 = ConvertTo-SecureString 'password1' -AsPlainText -Force
        $testLogin = 'getDbaInstanceRoleMemberLogin'
        $null = New-DbaLogin -SqlInstance $server2 -Login $testLogin -Password $password1
        $null = Set-DbaLogin -SqlInstance $server2 -Login $testLogin -AddRole 'dbcreator'

        $server1 = Connect-DbaInstance -SqlInstance $script:instance1
        $null = New-DbaLogin -SqlInstance $server1 -Login $testLogin -Password $password1
        $null = Set-DbaLogin -SqlInstance $server1 -Login $testLogin -AddRole 'dbcreator'
    }

    Context "Functionality" {
        It 'Returns all role membership for server roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2

            # should have at least $testLogin and a sysadmin
            $result.Count | Should -BeGreaterOrEqual 2
        }

        It 'Accepts a list of roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ServerRole 'sysadmin'

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Be 'sysadmin'
        }

        It 'Excludes roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ExcludeServerRole 'dbcreator'

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain 'dbcreator'
            $uniqueRoles | Should -Contain 'sysadmin'
        }

        It 'Excludes fixed roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -ExcludeFixedRole
            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain 'sysadmin'
        }

        It 'Filters by a specific login' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2 -Login $testLogin

            $uniqueLogins = $result.Name | Select-Object -Unique
            $uniqueLogins.Count | Should -BeExactly 1
            $uniqueLogins | Should -Contain $testLogin
        }

        It 'Returns results for all instances' {
            $result = Get-DbaServerRoleMember -SqlInstance $server2, $server1 -Login $testLogin

            $uniqueInstances = $result.SqlInstance | Select-Object -Unique
            $uniqueInstances.Count | Should -BeExactly 2
        }
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $server2 -Login $testLogin -Force -Confirm:$false
        Remove-DbaLogin -SqlInstance $server1 -Login $testLogin -Force -Confirm:$false
    }
}
