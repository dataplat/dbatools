param($ModuleName = 'dbatools')

Describe "Set-DbaNetworkConfiguration" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaNetworkConfiguration
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "EnableProtocol",
            "DisableProtocol",
            "DynamicPortForIPAll",
            "StaticPortForIPAll",
            "IpAddress",
            "RestartService",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command works with piped input" {
        BeforeAll {
            $netConf = Get-DbaNetworkConfiguration -SqlInstance $global:instance2
            $netConf.TcpIpProperties.KeepAlive = 60000
            $results = $netConf | Set-DbaNetworkConfiguration -Confirm:$false -WarningAction SilentlyContinue
        }

        It "Should Return a Result" {
            $results.ComputerName | Should -Be $netConf.ComputerName
        }

        It "Should Return a Change" {
            $results.Changes | Should -Match "Changed TcpIpProperties.KeepAlive to 60000"
        }

        AfterAll {
            $netConf = Get-DbaNetworkConfiguration -SqlInstance $global:instance2
            $netConf.TcpIpProperties.KeepAlive = 30000
            $null = $netConf | Set-DbaNetworkConfiguration -Confirm:$false -WarningAction SilentlyContinue
        }
    }

    Context "Command works with commandline input" {
        BeforeAll {
            $netConf = Get-DbaNetworkConfiguration -SqlInstance $global:instance2
            if ($netConf.NamedPipesEnabled) {
                $results = Set-DbaNetworkConfiguration -SqlInstance $global:instance2 -DisableProtocol NamedPipes -Confirm:$false -WarningAction SilentlyContinue
            } else {
                $results = Set-DbaNetworkConfiguration -SqlInstance $global:instance2 -EnableProtocol NamedPipes -Confirm:$false -WarningAction SilentlyContinue
            }
        }

        It "Should Return a Result" {
            $results.ComputerName | Should -Be $netConf.ComputerName
        }

        It "Should Return a Change" {
            $results.Changes | Should -Match "Changed NamedPipesEnabled to"
        }

        AfterAll {
            if ($netConf.NamedPipesEnabled) {
                $null = Set-DbaNetworkConfiguration -SqlInstance $global:instance2 -EnableProtocol NamedPipes -Confirm:$false -WarningAction SilentlyContinue
            } else {
                $null = Set-DbaNetworkConfiguration -SqlInstance $global:instance2 -DisableProtocol NamedPipes -Confirm:$false -WarningAction SilentlyContinue
            }
        }
    }
}
