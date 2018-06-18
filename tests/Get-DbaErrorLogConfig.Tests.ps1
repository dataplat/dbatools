$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaErrorLogConfig).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should -Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should -Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    Context "Get NumberErrorLog for multiple instances" {
        $results = Get-DbaErrorLogConfig -SqlInstance $script:instance3, $script:instance2
        foreach ($result in $results) {
            It 'Returns NumberErrorLog value' {
                $result.NumberErrorLogs | Should -Not -Be $null
            }
        }
    }

    Context "Get SizeInKb for multiple instances" {
        $results = Get-DbaErrorLogConfig -SqlInstance $script:instance3, $script:instance2
        foreach ($result in $results) {
            It 'Returns SizeInKb value' {
                $result.ErrorLogSizeKb | Should -Not -Be $null
            }
        }
    }

}