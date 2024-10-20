param($ModuleName = 'dbatools')

Describe "Get-DbaDbccHelp" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccHelp
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Statement",
            "IncludeUndocumented",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
