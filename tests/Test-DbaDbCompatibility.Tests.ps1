$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        # No specific setup needed for this command
    }
    AfterAll {
        # No specific cleanup needed for this command
    }

    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDbCompatibility -SqlInstance $TestConfig.instance2
            $results | Should -Not -Be $null
        }

        It "Should return a result for a database" {
            $results = Test-DbaDbCompatibility -Database Master -SqlInstance $TestConfig.instance2
            $results | Should -Not -Be $null
        }

        It "Should return a result excluding one database" {
            $results = Test-DbaDbCompatibility -ExcludeDatabase Master -SqlInstance $TestConfig.instance2
            $results | Should -Not -Be $null
        }
    }
}