$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Get NumberErrorLog for multiple instances" {
        $results = Get-DbaErrorLogConfig -SqlInstance $script:instance3, $script:instance2
        foreach ($result in $results) {
            It 'returns 3 values' {
                $result.LogCount | Should -Not -Be $null
                $result.LogSize | Should -Not -Be $null
                $result.LogPath | Should -Not -Be $null
            }
        }
    }
}