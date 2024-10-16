param($ModuleName = 'dbatools')

Describe "Add-DbaPfDataCollectorCounter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaPfDataCollectorCounter
        }
        It "Should have ComputerName as a non-mandatory DbaInstanceParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have CollectorSet as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[] -Not -Mandatory
        }
        It "Should have Collector as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Collector -Type String[] -Not -Mandatory
        }
        It "Should have Counter as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter Counter -Type Object[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "Add-DbaPfDataCollectorCounter Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate |
            Get-DbaPfDataCollector | Get-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' | Remove-DbaPfDataCollectorCounter -Confirm:$false
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Get-DbaPfDataCollector | Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
            $results.DataCollectorSet | Should -Be 'Long Running Queries'
            $results.Name | Should -Be '\LogicalDisk(*)\Avg. Disk Queue Length'
        }
    }
}
