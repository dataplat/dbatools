param($ModuleName = 'dbatools')

Describe "Get-DbaFeature" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFeature
        }
        $params = @(
            "ComputerName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying command works" {
        BeforeAll {
            $results = Get-DbaFeature | Select-Object -First 1
        }
        It "Returns a result with the right computername" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }
        It "Returns a result with a non-null name" {
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}
