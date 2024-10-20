param($ModuleName = 'dbatools')

Describe "Get-DbaSsisExecutionHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisExecutionHistory
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Since",
            "Status",
            "Project",
            "Folder",
            "Environment",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
