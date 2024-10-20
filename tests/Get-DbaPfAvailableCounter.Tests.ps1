param($ModuleName = 'dbatools')

Describe "Get-DbaPfAvailableCounter" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfAvailableCounter
        }

        It "has the required parameter: <_>" -ForEach $params {
            $params = @(
                "ComputerName",
                "Credential",
                "Pattern",
                "EnableException"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying command returns all the required results" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        }
        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet
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
