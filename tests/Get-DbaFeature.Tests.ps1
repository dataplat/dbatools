param($ModuleName = 'dbatools')

Describe "Get-DbaFeature" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFeature
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
