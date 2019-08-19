$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('WhatIf', 'Confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ServerRole', 'Login', 'Role', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $login1 = "dbatoolsci_login1_$(Get-Random)"
        $login2 = "dbatoolsci_login2_$(Get-Random)"
        $customServerRole = "dbatoolsci_customrole_$(Get-Random)"
        $fixedServerRoles = 'dbcreator','processadmin'
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $login1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $login2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaServerRole -SqlInstance $script:instance2 -ServerRole $customServerRole -Owner sa
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Remove-DbaLogin -SqlInstance $script:instance2 -Login $login1, $login2 -Confirm:$false
    }

    Context "Functionality" {
        It 'Adds Login to Role' {
            Add-DbaServerRoleMember -SqlInstance $script:instance2 -ServerRole $fixedServerRoles[0] -Login $login1 -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]

            $roleAfter.Role | Should -Be $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login1) | Should -Be $true
        }

        It 'Adds Login to Multiple Roles' {
            $serverRoles = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            Add-DbaServerRoleMember -SqlInstance $script:instance2 -ServerRole $serverRoles -Login $login1 -Confirm:$false

            $roleDBAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles
            $roleDBAfter.Count | Should -Be $serverRoles.Count
            $roleDBAfter.Login -contains $login1 | Should -Be $true

        }

        It 'Adds Customer Server-Level Role Membership' {
            Add-DbaServerRoleMember -SqlInstance $script:instance2 -ServerRole $customServerRole -Role $fixedServerRoles[-1] -Confirm:$false
            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[-1]

            $roleAfter.Role | Should -Be $fixedServerRoles[-1]
            $roleAfter.EnumMemberNames().Contains($customServerRole) | Should -Be $true
        }

        It 'Adds Login to Roles via piped input from Get-DbaServerRole' {
            $serverRole = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $serverRole | Add-DbaServerRoleMember -Login $login2 -Confirm:$false

            $roleAfter = Get-DbaServerRole -SqlInstance $server -ServerRole $fixedServerRoles[0]
            $roleAfter.EnumMemberNames().Contains($login2) | Should -Be $true
        }
    }
}