$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $current = Get-DbaAgHadr -SqlInstance $script:instance3 # for appveyor $script:instance2
        if ($current.IsHadrEnabled) {
            Disable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -WarningAction SilentlyContinue -Force
        }
    }
    AfterAll {
        if (-not $current.IsHadrEnabled) {
            Disable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -WarningAction SilentlyContinue -Force
        }
    }

    $results = Enable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -Force

    It "enables hadr" {
        $results.IsHadrEnabled | Should -Be $true
    }
}