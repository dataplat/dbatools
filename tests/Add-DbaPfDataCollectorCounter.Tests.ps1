param($ModuleName = 'dbatools')

Describe "Add-DbaPfDataCollectorCounter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaPfDataCollectorCounter
        }
        It "Should have ComputerName as a non-mandatory Dataplat.Dbatools.Parameter.DbaInstanceParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory System.Management.Automation.PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CollectorSet as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet
        }
        It "Should have Collector as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Collector
        }
        It "Should have Counter as a non-mandatory System.Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter Counter
        }
        It "Should have InputObject as a non-mandatory System.Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
