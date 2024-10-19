param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        It "Should have EnableException as a Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# ASync / Job based, no integration tests can be performed
