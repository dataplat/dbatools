param($ModuleName = 'dbatools')

Describe "Get-DbaBackupDevice" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaBackupDevice
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $sql = "EXEC sp_addumpdevice 'tape', 'dbatoolsci_tape', '\\.\tape0';"
            $server.Query($sql)
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $sql = "EXEC sp_dropdevice 'dbatoolsci_tape';"
            $server.Query($sql)
        }

        It "Gets the backup devices" {
            $results = Get-DbaBackupDevice -SqlInstance $script:instance2
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be "dbatoolsci_tape"
            $results.BackupDeviceType | Should -Be "Tape"
            $results.PhysicalLocation | Should -Be "\\.\Tape0"
        }
    }
}
