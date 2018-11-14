$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 20
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Import-DbaPfDataCollectorSetTemplate).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'DisplayName', 'SchedulesEnabled', 'RootPath', 'Segment', 'SegmentMaxDuration', 'SegmentMaxSize', 'Subdirectory', 'SubdirectoryFormat', 'SubdirectoryFormatPattern', 'Task', 'TaskRunAsSelf', 'TaskArguments', 'TaskUserTextArguments', 'StopOnCompletion', 'Path', 'Template', 'Instance', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results with pipe" {
        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
            $results.Name | Should Be 'Long Running Queries'
            $results.ComputerName | Should Be $env:COMPUTERNAME
        }
        It "returns only one (and the proper) template without pipe" {
            $results = Import-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries'
            $results.Name | Should Be 'Long Running Queries'
            $results.ComputerName | Should Be $env:COMPUTERNAME
        }
    }
}