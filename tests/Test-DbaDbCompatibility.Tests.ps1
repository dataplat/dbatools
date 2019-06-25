$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDbCompatibility -SqlInstance $script:instance2
            $results | Should -Not -Be $null
        }

        It "Should return a result for a database" {
            $results = Test-DbaDbCompatibility -Database Master -SqlInstance $script:instance2
            $results | Should -Not -Be $null
        }

        It "Should return a result excluding one database" {
            $results = Test-DbaDbCompatibility -ExcludeDatabase Master -SqlInstance $script:instance2
            $results | Should -Not -Be $null
        }
    }
}