param($ModuleName = 'dbatools')

Describe "Show-DbaInstanceFileSystem" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Show-DbaInstanceFileSystem
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

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
