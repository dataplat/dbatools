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
        $instance = Connect-DbaInstance -SqlInstance $script:instance2

        $password1 = ConvertTo-SecureString 'password1' -AsPlainText -Force
        $testLogin = 'getDbaInstanceRoleMemberLogin'
        $null = New-DbaLogin -SqlInstance $instance -Login $testLogin -Password $password1
        $null = Set-DbaLogin -SqlInstance $instance -Login $testLogin -AddRole 'dbcreator'
    }

    Context "Functionality" {
        It 'Returns all role membership for server roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $instance

            # should have at least $testLogin and a sysadmin
            $result.Count | Should -BeGreaterOrEqual 2
        }

        It 'Accepts a list of roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $instance -ServerRole 'sysadmin'

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Be 'sysadmin'
        }

        It 'Excludes roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $instance -ExcludeServerRole 'dbcreator'

            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain 'dbcreator'
            $uniqueRoles | Should -Contain 'sysadmin'
        }

        It 'Excludes fixed roles' {
            $result = Get-DbaServerRoleMember -SqlInstance $instance -ExcludeFixedRole
            $uniqueRoles = $result.Role | Select-Object -Unique
            $uniqueRoles | Should -Not -Contain 'sysadmin'
        }

        It 'Filters by a specific login' {
            $result = Get-DbaServerRoleMember -SqlInstance $instance -Login $testLogin

            $uniqueLogins = $result.Name | Select-Object -Unique
            $uniqueLogins.Count | Should -BeExactly 1
            $uniqueLogins | Should -Contain $testLogin
        }
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $instance -Login $testLogin -Force -Confirm:$false
    }
}