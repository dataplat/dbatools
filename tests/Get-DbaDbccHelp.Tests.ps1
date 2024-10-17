param($ModuleName = 'dbatools')

Describe "Get-DbaDbccHelp" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccHelp
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Statement as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Statement -Type String -Not -Mandatory
        }
        It "Should have IncludeUndocumented as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeUndocumented -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $props = 'Operation', 'Cmd', 'Output'
        }

        It "Returns the right results for FREESYSTEMCACHE" {
            $result = Get-DbaDbccHelp -SqlInstance $script:instance2 -Statement FREESYSTEMCACHE
            $result.Operation | Should -Be 'FREESYSTEMCACHE'
            $result.Cmd | Should -Be 'DBCC HELP(FREESYSTEMCACHE)'
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "Returns the right results for PAGE with IncludeUndocumented" {
            $result = Get-DbaDbccHelp -SqlInstance $script:instance2 -Statement PAGE -IncludeUndocumented
            $result.Operation | Should -Be 'PAGE'
            $result.Cmd | Should -Be 'DBCC HELP(PAGE)'
            $result.Output | Should -Not -BeNullOrEmpty
        }

        It "Returns expected properties" {
            $result = Get-DbaDbccHelp -SqlInstance $script:instance2 -Statement FREESYSTEMCACHE
            foreach ($prop in $props) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }
}
