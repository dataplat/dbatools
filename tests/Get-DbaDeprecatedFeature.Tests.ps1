$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        # Use a deprecated feature
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query 'SELECT * FROM sys.sysdatabases' -EnableException
    }

    Context "Gets Deprecated Features" {
        $results = Get-DbaDeprecatedFeature -SqlInstance $TestConfig.instance1
        It "Gets results" {
            $results.DeprecatedFeature | Should -Contain 'sysdatabases'
        }
    }
}
