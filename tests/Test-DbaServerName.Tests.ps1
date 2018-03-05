$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaServerName).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Detailed', 'ExcludeSsrs', 'EnableException'
        it "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        it "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
        It "Should throw on an invalid SQL Connection" {
            Mock -ModuleName 'dbatools' Connect-SqlInstance { throw }
            { Test-DbaServerName -SqlInstance 'MadeUpServer' -EnableException } | Should Throw
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    $server = Connect-DbaInstance -SqlInstance $script:instance2
    Context "Command tests servername" {
        $results = Test-DbaServerName -SqlInstance $script:instance2
        It "Should return the correct server" {
            $results.ComputerName | Should Be $server.NetName
        }
        It "Should return the correct instance" {
            $results.InstanceName | Should Be $server.ServiceName
        }
        It "Should return the correct server\instance" {
            $results.SqlInstance | Should Be $server.DomainInstanceName
        }
    }
}
