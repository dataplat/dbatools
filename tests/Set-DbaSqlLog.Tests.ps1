$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaSqlLog).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'SizeInKb', 'NumberOfLog', 'EnableException'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $currentNumLogFilesINSTANCE1 = $server.NumberOfLogFiles
        $currentErrorLogSizeKbINSTANCE1 = $server.ErrorLogSizeKb

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $currentNumLogFilesINSTANCE2 = $server.NumberOfLogFiles
        $currentErrorLogSizeKbINSTANCE2 = $server.ErrorLogSizeKb
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.NumberOfLogFiles = $currentNumLogFilesINSTANCE1 =
        $server.ErrorLogSizeKb = $currentErrorLogSizeKbINSTANCE1
        $server.Alter()

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.NumberOfLogFiles = $currentNumLogFilesINSTANCE2
        $server.ErrorLogSizeKb = $currentErrorLogSizeKbINSTANCE2
        $server.Alter()
    }
    Context "Apply NumberOfLog to multiple instances" {
        $results = Set-DbaSqlLog -SqlInstance $script:instance1, $script:instance2 -NumberOfLog 8
        foreach ($result in $results) {
            It 'Returns NumberOfLog set to 3 for each instance' {
                $result.CurrentNumberErrorLogs | Should Be 8
            }
        }
    }
    Context "Apply SizeInKb to multiple instances" {
        $results = Set-DbaSqlLog -SqlInstance $script:instance1, $script:instance2 -SizeInKb 100
        foreach ($result in $results) {
            It 'Returns SizeInKb set to 100 for each instance' {
                $result.CurrentErrorLogSizeKb | Should Be 100
            }
        }
    }
}