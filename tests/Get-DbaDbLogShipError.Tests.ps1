param($ModuleName = 'dbatools')

Describe "Get-DbaDbLogShipError Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing necessary module or setting up environment if needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = Get-Command Get-DbaDbLogShipError
        }
        It "Should have SqlInstance as a parameter" {
            $CommandName | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandName | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandName | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandName | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Action as a parameter" {
            $CommandName | Should -HaveParameter Action
        }
        It "Should have DateTimeFrom as a parameter" {
            $CommandName | Should -HaveParameter DateTimeFrom
        }
        It "Should have DateTimeTo as a parameter" {
            $CommandName | Should -HaveParameter DateTimeTo
        }
        It "Should have Primary as a parameter" {
            $CommandName | Should -HaveParameter Primary
        }
        It "Should have Secondary as a parameter" {
            $CommandName | Should -HaveParameter Secondary
        }
        It "Should have EnableException as a parameter" {
            $CommandName | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaDbLogShipError Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        # Setup code for integration tests
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Return values" {
        It "Get the log shipping errors" {
            $Results = Get-DbaDbLogShipError -SqlInstance $global:instance2
            $Results.Count | Should -Be 0
        }
    }
}
