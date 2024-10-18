param($ModuleName = 'dbatools')

Describe "Get-DbaDbFileGrowth" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFileGrowth
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" {
        It "Should return file information" {
            $result = Get-DbaDbFileGrowth -SqlInstance $global:instance2
            $result.Database | Should -Contain "msdb"
        }

        It "Should return file information for only msdb" {
            $result = Get-DbaDbFileGrowth -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1
            $result.Database | Should -Be "msdb"
        }
    }
}
