$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaSqlLog).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'SizeInKb', 'NumberLog', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    Context "Apply NumOfLog to multiple instances" {
        $results = Set-DbaMaxDop -SqlInstance $script:instance1, $script:instance2 -NumOfLog 3
        foreach ($result in $results) {
            It 'Returns NumOfLog set to 3 for each instance' {
                $result.CurrentNumberErrorLog | Should Be 3
            }
        }
    }

    Context "Apply SizeInKb to multiple instances" {
        $results = Set-DbaMaxDop -SqlInstance $script:instance1, $script:instance2 -SizeInKb 100
        foreach ($result in $results) {
            It 'Returns SizeInKb set to 100 for each instance' {
                $result.CurrentErrorLogSizeInKb | Should Be 100
            }
        }
    }

}