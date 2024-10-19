param($ModuleName = 'dbatools')
Describe "Stop-DbaPfDataCollectorSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaPfDataCollectorSet
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "InputObject",
                "NoWait",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $env:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
            $env:set | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        AfterAll {
            $env:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }
        It "returns a result with the right computername and name is not null" {
            $results = $env:set | Select-Object -First 1 | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}
