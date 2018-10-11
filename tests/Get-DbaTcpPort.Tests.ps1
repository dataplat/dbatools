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

        It "Should Return a Result" {
            $server = Get-DbaTcpPort -SqlInstance $script:instance2
            $server | Should Not Be $null
        }

        It "Should Return Multiple Results" {
            $server = Get-DbaTcpPort -SqlInstance $script:instance2 -All
            $server.Count | Should BeGreaterThan 1
        }

        It "Should Throw an Error if SqlInstance doesn't exist" {
            { Get-DbaTcpPort -SqlInstance "ThisIsNotAnInstance" -All | Should Throw }
        }
    }
}