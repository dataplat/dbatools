$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Spid', 'ExcludeSpid', 'Database', 'Login', 'Hostname', 'Program', 'ExcludeSystemSpids', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing Get-DbaProcess results" {
        $results = Get-DbaProcess -SqlInstance $TestConfig.instance1

        It "matches self as a login at least once" {
            $matching = $results | Where-Object Login -match $env:username
            $matching | Should -Not -BeNullOrEmpty
        }

        $results = Get-DbaProcess -SqlInstance $TestConfig.instance1 -Program 'dbatools PowerShell module - dbatools.io'

        foreach ($result in $results) {
            It "returns only dbatools processes" {
                $result.Program -eq 'dbatools PowerShell module - dbatools.io' | Should Be $true
            }
        }

        $results = Get-DbaProcess -SqlInstance $TestConfig.instance1 -Database master

        foreach ($result in $results) {
            It "returns only processes from master database" {
                $result.Database -eq 'master' | Should Be $true
            }
        }
    }
}
