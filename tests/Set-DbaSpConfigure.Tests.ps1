param($ModuleName = 'dbatools')

Describe "Set-DbaSpConfigure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaSpConfigure
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Value as a parameter" {
            $CommandUnderTest | Should -HaveParameter Value
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Set configuration" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $remotequerytimeout = (Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newtimeout = $remotequerytimeout + 1
        }

        It "changes the remote query timeout from $remotequerytimeout to $newtimeout" {
            $results = Set-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout -Value $newtimeout
            $results.PreviousValue | Should -Be $remotequerytimeout
            $results.NewValue | Should -Be $newtimeout
        }

        It "changes the remote query timeout from $newtimeout to $remotequerytimeout" {
            $results = Set-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout
            $results.PreviousValue | Should -Be $newtimeout
            $results.NewValue | Should -Be $remotequerytimeout
        }

        It "returns a warning when if the new value is the same as the old" {
            $warning = $null
            $results = Set-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout -WarningVariable warning -WarningAction SilentlyContinue
            $warning | Should -Match "existing"
        }
    }
}
