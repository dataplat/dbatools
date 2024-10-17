param($ModuleName = 'dbatools')

Describe "Measure-DbatoolsImport" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Measure-DbatoolsImport
        }
        It "Should have no parameters" {
            $CommandUnderTest.Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') } | Should -BeNullOrEmpty
        }
    }

    Context "Command usage" {
        It "Should not throw when executed" {
            { Measure-DbatoolsImport } | Should -Not -Throw
        }

        It "Should return a result" {
            $result = Measure-DbatoolsImport
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return a timespan" {
            $result = Measure-DbatoolsImport
            $result | Should -BeOfType [System.TimeSpan]
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
