param($ModuleName = 'dbatools')

Describe "Get-DbaDbccHelp" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccHelp
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Statement as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Statement -Type System.String -Mandatory:$false
        }
        It "Should have IncludeUndocumented as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeUndocumented -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $props = 'Operation', 'Cmd', 'Output'
        }

        It "Returns the right results for FREESYSTEMCACHE" {
            $result = Get-DbaDbccHelp -SqlInstance $global:instance2 -Statement FREESYSTEMCACHE
            $result.Operation | Should -Be 'FREESYSTEMCACHE'
            $result.Cmd | Should -Be 'DBCC HELP(FREESYSTEMCACHE)'
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "Returns the right results for PAGE with IncludeUndocumented" {
            $result = Get-DbaDbccHelp -SqlInstance $global:instance2 -Statement PAGE -IncludeUndocumented
            $result.Operation | Should -Be 'PAGE'
            $result.Cmd | Should -Be 'DBCC HELP(PAGE)'
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "Returns expected properties" {
            $result = Get-DbaDbccHelp -SqlInstance $global:instance2 -Statement FREESYSTEMCACHE
            foreach ($prop in $props) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }
}
