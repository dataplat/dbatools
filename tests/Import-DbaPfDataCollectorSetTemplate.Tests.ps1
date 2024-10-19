param($ModuleName = 'dbatools')

Describe "Import-DbaPfDataCollectorSetTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaPfDataCollectorSetTemplate
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "DisplayName",
                "SchedulesEnabled",
                "RootPath",
                "Segment",
                "SegmentMaxDuration",
                "SegmentMaxSize",
                "Subdirectory",
                "SubdirectoryFormat",
                "SubdirectoryFormatPattern",
                "Task",
                "TaskRunAsSelf",
                "TaskArguments",
                "TaskUserTextArguments",
                "StopOnCompletion",
                "Path",
                "Template",
                "Instance",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
        }
        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
        }

        It "returns only one (and the proper) template with pipe" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
            $results.Name | Should -Be 'Long Running Queries'
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It "returns only one (and the proper) template without pipe" {
            $results = Import-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries'
            $results.Name | Should -Be 'Long Running Queries'
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }
    }
}
