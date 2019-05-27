$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Force', 'Classic', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Should Copy Objects to the same instance" {
        $results = Copy-DbaSysDbUserObject -Source $script:instance2 -Destination $script:instance2
        It "Should execute with default parameters" {
            $results | Should Not Be Null
        }
        $results = Copy-DbaSysDbUserObject -Source $script:instance2 -Destination $script:instance2 -Classic
        It "Should execute with -Classic parameter" {
            $results | Should Not Be Null
        }
    }
}