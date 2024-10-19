param($ModuleName = 'dbatools')

Describe "Import-DbaPfDataCollectorSetTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaPfDataCollectorSetTemplate
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have DisplayName as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisplayName
        }
        It "Should have SchedulesEnabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SchedulesEnabled
        }
        It "Should have RootPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter RootPath
        }
        It "Should have Segment as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Segment
        }
        It "Should have SegmentMaxDuration as a parameter" {
            $CommandUnderTest | Should -HaveParameter SegmentMaxDuration
        }
        It "Should have SegmentMaxSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter SegmentMaxSize
        }
        It "Should have Subdirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter Subdirectory
        }
        It "Should have SubdirectoryFormat as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubdirectoryFormat
        }
        It "Should have SubdirectoryFormatPattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubdirectoryFormatPattern
        }
        It "Should have Task as a parameter" {
            $CommandUnderTest | Should -HaveParameter Task
        }
        It "Should have TaskRunAsSelf as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter TaskRunAsSelf
        }
        It "Should have TaskArguments as a parameter" {
            $CommandUnderTest | Should -HaveParameter TaskArguments
        }
        It "Should have TaskUserTextArguments as a parameter" {
            $CommandUnderTest | Should -HaveParameter TaskUserTextArguments
        }
        It "Should have StopOnCompletion as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter StopOnCompletion
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Template as a parameter" {
            $CommandUnderTest | Should -HaveParameter Template
        }
        It "Should have Instance as a parameter" {
            $CommandUnderTest | Should -HaveParameter Instance
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
