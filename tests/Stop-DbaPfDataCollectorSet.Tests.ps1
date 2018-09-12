$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $script:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
        $script:set | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        Start-Sleep 2
    }
    AfterAll {
        $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
    }
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = $script:set | Select-Object -First 1 | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should Be $env:COMPUTERNAME
                $results.Name | Should Not Be $null
            }
        }
    }
}