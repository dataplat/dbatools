$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'All', 'ExcludeIpv6', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaTcpPort -SqlInstance $script:instance2
        $resultsIpv6 = Get-DbaTcpPort -SqlInstance $script:instance2 -All -ExcludeIpv6
        $resultsAll = Get-DbaTcpPort -SqlInstance $script:instance2 -All

        It "Should Return a Result" {
            $results | Should -Not -Be $null
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,IPAddress,Port,Static,Type'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Should Return Multiple Results" {
            $resultsAll.Count | Should -BeGreaterThan 1
        }

        It "Should Exclude Ipv6 Results" {
            $resultsAll.Count - $resultsIpv6.Count | Should -BeGreaterThan 0
        }
    }
}