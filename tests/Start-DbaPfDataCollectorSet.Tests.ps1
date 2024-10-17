param($ModuleName = 'dbatools')

Describe "Start-DbaPfDataCollectorSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaPfDataCollectorSet
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have CollectorSet as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have NoWait as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoWait -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $script:set = Get-DbaPfDataCollectorSet | Select-Object -First 1
            $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        AfterAll {
            $script:set | Stop-DbaPfDataCollectorSet -WarningAction SilentlyContinue
        }

        It "returns a result with the right computername and name is not null" {
            $results = $script:set | Select-Object -First 1 | Start-DbaPfDataCollectorSet -WarningAction SilentlyContinue -WarningVariable warn
            if (-not $warn) {
                $results.ComputerName | Should -Be $env:COMPUTERNAME
                $results.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}
