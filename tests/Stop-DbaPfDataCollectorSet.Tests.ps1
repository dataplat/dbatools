param($ModuleName = 'dbatools')
Describe "Stop-DbaPfDataCollectorSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaPfDataCollectorSet
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have NoWait as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoWait
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
