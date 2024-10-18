param($ModuleName = 'dbatools')

Describe "Get-DbaBackupDevice" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaBackupDevice
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
