param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        It "Should have EnableException as a Switch that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
        It "Should have Verbose as a Switch that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Mandatory:$false
        }
        It "Should have Debug as a Switch that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Mandatory:$false
        }
        It "Should have ErrorAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have WarningAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have InformationAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have ProgressAction as an ActionPreference that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have ErrorVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type string -Mandatory:$false
        }
        It "Should have WarningVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type string -Mandatory:$false
        }
        It "Should have InformationVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type string -Mandatory:$false
        }
        It "Should have OutVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type string -Mandatory:$false
        }
        It "Should have OutBuffer as an Int32 that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type int -Mandatory:$false
        }
        It "Should have PipelineVariable as a String that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type string -Mandatory:$false
        }
    }
}

# ASync / Job based, no integration tests can be performed
