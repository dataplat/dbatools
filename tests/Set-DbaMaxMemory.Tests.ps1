$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Max', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $inst1CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.instance1).MaxValue
        $inst2CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $TestConfig.instance2).MaxValue
    }
    AfterAll {
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.instance1 -Max $inst1CurrentMaxValue
        $null = Set-DbaMaxMemory -SqlInstance $TestConfig.instance2 -Max $inst2CurrentMaxValue
    }
    Context "Connects to multiple instances" {
        $results = Set-DbaMaxMemory -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Max 1024
        foreach ($result in $results) {
            It 'Returns 1024  for each instance' {
                $result.MaxValue | Should Be 1024
            }
        }
    }
}
