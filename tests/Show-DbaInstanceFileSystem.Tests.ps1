param($ModuleName = 'dbatools')

Describe "Show-DbaInstanceFileSystem" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Show-DbaInstanceFileSystem
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
