param($ModuleName = 'dbatools')

Describe "Get-DbaStartupParameter" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaStartupParameter
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have Simple as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Simple -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have common parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaStartupParameter -SqlInstance $global:instance2
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
