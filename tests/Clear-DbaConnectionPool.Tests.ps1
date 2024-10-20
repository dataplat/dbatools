param($ModuleName = 'dbatools')

Describe "Clear-DbaConnectionPool" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Clear-DbaConnectionPool
        }
        $parms = @(
            'ComputerName',
            'Credential',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command Execution" {
        It "doesn't throw" {
            { Clear-DbaConnectionPool } | Should -Not -Throw
        }
    }
}
