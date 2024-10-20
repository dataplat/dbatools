param($ModuleName = 'dbatools')

Describe "Get-DbaWsfcNode" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWsfcNode
        }

        It "has all the required parameters" {
            $params = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Get-DbaWsfcNode
}
