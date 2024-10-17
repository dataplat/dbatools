param($ModuleName = 'dbatools')
Describe "Stop-DbaPfDataCollectorSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaPfDataCollectorSet
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have CollectorSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have NoWait as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoWait -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
