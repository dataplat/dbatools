param($ModuleName = 'dbatools')

Describe "Get-DbaPfAvailableCounter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfAvailableCounter
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have Pattern as a parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Verifying command returns all the required results" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        }
        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
        }

        It "returns the correct values" {
            $results = Get-DbaPfAvailableCounter
            $results.Count | Should -BeGreaterThan 1000
        }

        It "returns are pipable into Add-DbaPfDataCollectorCounter" {
            $results = Get-DbaPfAvailableCounter -Pattern *sql* | Select-Object -First 3 | Add-DbaPfDataCollectorCounter -CollectorSet 'Long Running Queries' -Collector DataCollector01 -WarningAction SilentlyContinue
            foreach ($result in $results) {
                $result.Name | Should -Match "sql"
            }
        }
    }
}
