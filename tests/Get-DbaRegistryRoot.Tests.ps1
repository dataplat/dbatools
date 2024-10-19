param($ModuleName = 'dbatools')

Describe "Get-DbaRegistryRoot" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegistryRoot
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

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaRegistryRoot
            $regexpath = "Software\\Microsoft\\Microsoft SQL Server"
        }

        It "Returns at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns at least one named instance if more than one result is returned" -Skip:($results.Count -le 1) {
            $named = $results | Where-Object SqlInstance -Match '\\'
            $named | Should -Not -BeNullOrEmpty
        }

        It "Returns non-null values for Hive and SqlInstance" {
            foreach ($result in $results) {
                $result.Hive | Should -Not -BeNullOrEmpty
                $result.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }

        It "Returns RegistryRoot that matches 'Software\Microsoft\Microsoft SQL Server'" {
            foreach ($result in $results) {
                $result.RegistryRoot | Should -Match $regexpath
            }
        }
    }
}
