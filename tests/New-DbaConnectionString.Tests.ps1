$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 24
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\New-DbaConnectionString).Parameters.Keys
        $knownParameters = 'SqlInstance', 'Credential', 'AccessToken', 'ApplicationIntent', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'FailoverPartner', 'IsActiveDirectoryUniversalAuth', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AppendConnectionString'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>