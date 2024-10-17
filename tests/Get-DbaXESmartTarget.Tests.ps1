param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        It "Should have EnableException as a SwitchParameter that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
        It "Should have Verbose as a SwitchParameter that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Not -Mandatory
        }
        It "Should have Debug as a SwitchParameter that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Not -Mandatory
        }
        It "Should have ErrorAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type string -Not -Mandatory
        }
        It "Should have WarningVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type string -Not -Mandatory
        }
        It "Should have InformationVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type string -Not -Mandatory
        }
        It "Should have OutVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type string -Not -Mandatory
        }
        It "Should have OutBuffer as an Int32 that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type int -Not -Mandatory
        }
        It "Should have PipelineVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type string -Not -Mandatory
        }
    }
}

# ASync / Job based, no integration tests can be performed
