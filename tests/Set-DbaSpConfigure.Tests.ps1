param($ModuleName = 'dbatools')

Describe "Set-DbaSpConfigure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaSpConfigure
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Value",
            "Name",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
