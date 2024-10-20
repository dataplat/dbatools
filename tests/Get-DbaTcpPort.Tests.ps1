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

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "All",
            "ExcludeIpv6",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
