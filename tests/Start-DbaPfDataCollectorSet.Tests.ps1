$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CollectorSet', 'InputObject', 'NoWait', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $script:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
        $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        Start-Sleep 2
    }
    AfterAll {
        $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
    }
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = $script:set | Select-Object -First 1 | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should Be $env:COMPUTERNAME
                $results.Name | Should Not Be $null
            }
        }
    }
}