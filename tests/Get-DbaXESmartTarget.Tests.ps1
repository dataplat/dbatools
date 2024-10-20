param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

# ASync / Job based, no integration tests can be performed
