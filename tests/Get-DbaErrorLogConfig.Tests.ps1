$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaErrorLogConfig).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should -Be $knownParameters.Count
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