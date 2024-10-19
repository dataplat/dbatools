param($ModuleName = 'dbatools')

Describe "Get-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESmartTarget
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "EnableException",
                "SqlInstance",
                "SqlCredential"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# ASync / Job based, no integration tests can be performed
