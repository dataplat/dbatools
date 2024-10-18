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
            $CommandName | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandName | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandName | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandName | Should -HaveParameter ExcludeDatabase -Type System.String[] -Mandatory:$false
        }
        It "Should have Action as a parameter" {
            $CommandName | Should -HaveParameter Action -Type System.String[] -Mandatory:$false
        }
        It "Should have DateTimeFrom as a parameter" {
            $CommandName | Should -HaveParameter DateTimeFrom -Type System.DateTime -Mandatory:$false
        }
        It "Should have DateTimeTo as a parameter" {
            $CommandName | Should -HaveParameter DateTimeTo -Type System.DateTime -Mandatory:$false
        }
        It "Should have Primary as a parameter" {
            $CommandName | Should -HaveParameter Primary -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Secondary as a parameter" {
            $CommandName | Should -HaveParameter Secondary -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandName | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
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
