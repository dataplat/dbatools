param($ModuleName = 'dbatools')

Describe "Get-DbaTcpPort" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaTcpPort
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have All as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter All
        }
        It "Should have ExcludeIpv6 as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeIpv6
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaTcpPort -SqlInstance $global:instance2
            $resultsIpv6 = Get-DbaTcpPort -SqlInstance $global:instance2 -All -ExcludeIpv6
            $resultsAll = Get-DbaTcpPort -SqlInstance $global:instance2 -All
        }

        It "Should Return a Result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'IPAddress', 'Port', 'Static', 'Type'
            $result.PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Should Return Multiple Results" {
            $resultsAll.Count | Should -BeGreaterThan 1
        }

        It "Should Exclude Ipv6 Results" {
            $resultsAll.Count - $resultsIpv6.Count | Should -BeGreaterThan 0
        }
    }
}
