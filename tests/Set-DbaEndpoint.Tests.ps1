param($ModuleName = 'dbatools')

Describe "Set-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaEndpoint
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Endpoint",
            "Owner",
            "Type",
            "AllEndpoints",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}
