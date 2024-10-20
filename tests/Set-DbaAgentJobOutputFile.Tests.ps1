param($ModuleName = 'dbatools')

Describe "Set-DbaAgentJobOutputFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJobOutputFile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Job",
            "Step",
            "OutputFile",
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
