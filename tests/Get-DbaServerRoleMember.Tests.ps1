$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ServerRole', 'ExcludeServerRole', 'Login', 'ExcludeFixedRole', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
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