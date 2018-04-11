$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $inst1CurrentSqlMax = (Get-DbaMaxMemory -SqlInstance $script:instance1).SqlMaxMB
        $inst2CurrentSqlMax = (Get-DbaMaxMemory -SqlInstance $script:instance2).SqlMaxMB
    }
    AfterAll {
       $null = Set-DbaMaxMemory -SqlInstance $script:instance1 -MaxMB $inst1CurrentSqlMax
       $null = Set-DbaMaxMemory -SqlInstance $script:instance2 -MaxMB $inst2CurrentSqlMax
    }
    Context "Connects to multiple instances" {
        $results = Set-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2 -MaxMB 1024
        foreach ($result in $results) {
            It 'Returns 1024 MB for each instance' {
                $result.CurrentMaxValue | Should Be 1024
            }
        }
    }
}

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    InModuleScope dbatools {
        Context 'Validate input arguments' {
            It 'SqlInstance parameter host cannot be found' {
                Set-DbaMaxMemory -SqlInstance 'ABC' 3> $null | Should be $null
            }
        }
    }
}
