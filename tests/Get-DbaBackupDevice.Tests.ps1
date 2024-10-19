param($ModuleName = 'dbatools')

Describe "Get-DbaBackupDevice" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaBackupDevice
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC sp_addumpdevice 'tape', 'dbatoolsci_tape', '\\.\tape0';"
            $server.Query($sql)
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC sp_dropdevice 'dbatoolsci_tape';"
            $server.Query($sql)
        }

        It "Gets the backup devices" {
            $results = Get-DbaBackupDevice -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be "dbatoolsci_tape"
            $results.BackupDeviceType | Should -Be "Tape"
            $results.PhysicalLocation | Should -Be "\\.\Tape0"
        }
    }
}
