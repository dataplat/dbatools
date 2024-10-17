param($ModuleName = 'dbatools')

Describe "Get-DbaAgentProxy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentProxy
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Proxy as a parameter" {
            $CommandUnderTest | Should -HaveParameter Proxy -Type String[]
        }
        It "Should have ExcludeProxy as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeProxy -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            $tUserName = "dbatoolsci_proxytest"
            New-LocalUser -Name $tUserName -Password $tPassword -Disabled:$false
            New-DbaCredential -SqlInstance $script:instance2 -Name "$tUserName" -Identity "$env:COMPUTERNAME\$tUserName" -Password $tPassword
            New-DbaAgentProxy -SqlInstance $script:instance2 -Name STIG -ProxyCredential "$tUserName"
            New-DbaAgentProxy -SqlInstance $script:instance2 -Name STIGX -ProxyCredential "$tUserName"
        }

        AfterAll {
            $tUserName = "dbatoolsci_proxytest"
            Remove-LocalUser -Name $tUserName
            $credential = Get-DbaCredential -SqlInstance $script:instance2 -Name $tUserName
            $credential.DROP()
            $proxy = Get-DbaAgentProxy -SqlInstance $script:instance2 -Proxy "STIG", "STIGX"
            $proxy.DROP()
        }

        Context "Gets the list of Proxy" {
            BeforeAll {
                $results = Get-DbaAgentProxy -SqlInstance $script:instance2
            }

            It "Results are not empty" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have the name STIG" {
                $results.name | Should -Contain "STIG"
            }

            It "Should be enabled" {
                $results.isenabled | Should -Contain $true
            }
        }

        Context "Gets a single Proxy" {
            BeforeAll {
                $results = Get-DbaAgentProxy -SqlInstance $script:instance2 -Proxy "STIG"
            }

            It "Results are not empty" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have the name STIG" {
                $results.name | Should -Be "STIG"
            }

            It "Should be enabled" {
                $results.isenabled | Should -Be $true
            }
        }

        Context "Gets the list of Proxy without excluded" {
            BeforeAll {
                $results = Get-DbaAgentProxy -SqlInstance $script:instance2 -ExcludeProxy "STIG"
            }

            It "Results are not empty" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should not have the name STIG" {
                $results.name | Should -Not -Be "STIG"
            }

            It "Should be enabled" {
                $results.isenabled | Should -Be $true
            }
        }
    }
}
