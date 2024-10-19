param($ModuleName = 'dbatools')

Describe "New-DbaDbRole" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $instance = Connect-DbaInstance -SqlInstance $global:instance2
        $dbname = "dbatoolsci_adddb_newrole"
        $instance.Query("create database $dbname")
        $roleExecutor = "dbExecuter"
        $roleSPAccess = "dbSPAccess"
        $owner = 'dbo'
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $instance -Database $dbname -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbRole
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Role as a parameter" {
            $CommandUnderTest | Should -HaveParameter Role
        }
        It "Should have Owner as a parameter" {
            $CommandUnderTest | Should -HaveParameter Owner
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Functionality" {
        BeforeEach {
            $null = Remove-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor, $roleSPAccess -Confirm:$false
        }

        It 'Add new role and returns results' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Parent | Should -Be $dbname
        }

        It 'Add new role with specified owner' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor -Owner $owner

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Owner | Should -Be $owner
            $result.Parent | Should -Be $dbname
        }

        It 'Add two new roles and returns results' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor, $roleSPAccess

            $result.Count | Should -Be 2
            $result.Name | Should -Contain $roleExecutor
            $result.Name | Should -Contain $roleSPAccess
            $result.Parent | Select-Object -Unique | Should -Be $dbname
        }

        It 'Accept database as inputObject' {
            $result = $instance.Databases[$dbname] | New-DbaDbRole -Role $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Parent | Should -Be $dbname
        }
    }
}
