param($ModuleName = 'dbatools')

Describe "Import-DbaPfDataCollectorSetTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaPfDataCollectorSetTemplate
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have DisplayName as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisplayName -Type String
        }
        It "Should have SchedulesEnabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SchedulesEnabled -Type Switch
        }
        It "Should have RootPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter RootPath -Type String
        }
        It "Should have Segment as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Segment -Type Switch
        }
        It "Should have SegmentMaxDuration as a parameter" {
            $CommandUnderTest | Should -HaveParameter SegmentMaxDuration -Type Int32
        }
        It "Should have SegmentMaxSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter SegmentMaxSize -Type Int32
        }
        It "Should have Subdirectory as a parameter" {
            $CommandUnderTest | Should -HaveParameter Subdirectory -Type String
        }
        It "Should have SubdirectoryFormat as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubdirectoryFormat -Type Int32
        }
        It "Should have SubdirectoryFormatPattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubdirectoryFormatPattern -Type String
        }
        It "Should have Task as a parameter" {
            $CommandUnderTest | Should -HaveParameter Task -Type String
        }
        It "Should have TaskRunAsSelf as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter TaskRunAsSelf -Type Switch
        }
        It "Should have TaskArguments as a parameter" {
            $CommandUnderTest | Should -HaveParameter TaskArguments -Type String
        }
        It "Should have TaskUserTextArguments as a parameter" {
            $CommandUnderTest | Should -HaveParameter TaskUserTextArguments -Type String
        }
        It "Should have StopOnCompletion as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter StopOnCompletion -Type Switch
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[]
        }
        It "Should have Template as a parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[]
        }
        It "Should have Instance as a parameter" {
            $CommandUnderTest | Should -HaveParameter Instance -Type String[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
