param($ModuleName = 'dbatools')

Describe "Get-DbaSsisEnvironmentVariable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisEnvironmentVariable
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Environment",
            "EnvironmentExclude",
            "Folder",
            "FolderExclude",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
