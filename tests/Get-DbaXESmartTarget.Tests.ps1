param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        It "Should have EnableException as a Switch that is not mandatory" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

# ASync / Job based, no integration tests can be performed
