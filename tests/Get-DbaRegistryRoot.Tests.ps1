param($ModuleName = 'dbatools')

Describe "Get-DbaRegistryRoot" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegistryRoot
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
