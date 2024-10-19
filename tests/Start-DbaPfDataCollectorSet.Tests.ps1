param($ModuleName = 'dbatools')

Describe "Start-DbaPfDataCollectorSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaPfDataCollectorSet
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CollectorSet as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have NoWait as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoWait
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            $env:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
            $env:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        AfterAll {
            $env:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }

        It "returns a result with the right computername and name is not null" {
            $results = $env:set | Select-Object -First 1 | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}
