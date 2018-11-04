$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'MaxMB', 'EnableException'
        $SupportShouldProcess = $true
        $paramCount = $knownParameters.Count
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        }
        else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

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
    Context 'Validate input arguments' {
        It 'SqlInstance parameter host cannot be found' {
            Set-DbaMaxMemory -SqlInstance 'ABC' 3> $null | Should be $null
        }
    }
}


