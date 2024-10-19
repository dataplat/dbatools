param($ModuleName = 'dbatools')

Describe "Set-DbaNetworkConfiguration" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaNetworkConfiguration
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableProtocol as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableProtocol
        }
        It "Should have DisableProtocol as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DisableProtocol
        }
        It "Should have DynamicPortForIPAll as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter DynamicPortForIPAll
        }
        It "Should have StaticPortForIPAll as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter StaticPortForIPAll
        }
        It "Should have IpAddress as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter IpAddress
        }
        It "Should have RestartService as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter RestartService
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
