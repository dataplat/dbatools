param($ModuleName = 'dbatools')

Describe "Get-DbaRegistryRoot" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRegistryRoot
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
        # Common parameters
        @('Verbose', 'Debug', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable') | ForEach-Object {
            It "Should have $_ as a common parameter" {
                $CommandUnderTest | Should -HaveParameter $_
            }
        }
        @('ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction') | ForEach-Object {
            It "Should have $_ as a common parameter of Type System.Management.Automation.ActionPreference" {
                $CommandUnderTest | Should -HaveParameter $_ -Type System.Management.Automation.ActionPreference
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
