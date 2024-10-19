param($ModuleName = 'dbatools')

Describe "Remove-DbaServerRole Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaServerRole
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have ServerRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Remove-DbaServerRole Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $global:instance2
        $roleExecutor = "serverExecuter"
        $null = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
    }

    AfterAll {
        $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
    }

    Context "Command actually works" {
        It "It returns info about server-role removed" {
            $results = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Confirm:$false
            $results.ServerRole | Should -Be $roleExecutor
        }

        It "Should not return server-role" {
            $results = Get-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor
            $results | Should -BeNullOrEmpty
        }
    }
}
