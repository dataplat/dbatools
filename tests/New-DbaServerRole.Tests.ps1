param($ModuleName = 'dbatools')

Describe "New-DbaServerRole" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaServerRole
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "ServerRole",
            "Owner",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $instance = Connect-DbaInstance -SqlInstance $global:instance2
            $roleExecutor = "serverExecuter"
            $roleMaster = "serverMaster"
            $owner = "sa"
        }
        AfterEach {
            $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster
        }

        It 'Add new server-role and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
        }

        It 'Add new server-role with specified owner' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Owner $owner

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Owner | Should -Be $owner
        }

        It 'Add two new server-roles and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster

            $result.Count | Should -Be 2
            $result.Name | Should -Contain $roleExecutor
            $result.Name | Should -Contain $roleMaster
        }
    }
}
