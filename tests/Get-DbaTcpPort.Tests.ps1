$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.

            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
                      #>
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaTcpPort).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'All', 'ExcludeIpv6', 'EnableException', 'Detailed'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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