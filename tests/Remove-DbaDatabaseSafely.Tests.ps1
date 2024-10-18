param($ModuleName = 'dbatools')

Describe "Remove-DbaDatabaseSafely" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDatabaseSafely
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have Destination as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter -Mandatory:$false
        }
        It "Should have DestinationSqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have NoDbccCheckDb as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoDbccCheckDb -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have BackupFolder as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter BackupFolder -Type System.String -Mandatory:$false
        }
        It "Should have CategoryName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter CategoryName -Type System.String -Mandatory:$false
        }
        It "Should have JobOwner as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter JobOwner -Type System.String -Mandatory:$false
        }
        It "Should have AllDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllDatabases -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have BackupCompression as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter BackupCompression -Type System.String -Mandatory:$false
        }
        It "Should have ReuseSourceFolderStructure as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReuseSourceFolderStructure -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $db1 = "dbatoolsci_safely"
            $db2 = "dbatoolsci_safely_otherInstance"
            $server3 = Connect-DbaInstance -SqlInstance $global:instance3
            $server3.Query("CREATE DATABASE $db1")
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $server2.Query("CREATE DATABASE $db1")
            $server2.Query("CREATE DATABASE $db2")
            $server1 = Connect-DbaInstance -SqlInstance $global:instance1
        }

        AfterAll {
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1, $db2
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance3 -Database $db1
            $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $global:instance2 -Job 'Rationalised Database Restore Script for dbatoolsci_safely'
            $null = Remove-DbaAgentJob -Confirm:$false -SqlInstance $global:instance3 -Job 'Rationalised Database Restore Script for dbatoolsci_safely_otherInstance'
        }

        It "Should have database name of $db1" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $global:instance2 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb
            foreach ($result in $results) {
                $result.DatabaseName | Should -Be $db1
            }
        }

        It "Should warn and quit on Express Edition" -Skip:($server1.EngineEdition -notmatch "Express") {
            $results = Remove-DbaDatabaseSafely -SqlInstance $global:instance1 -Database $db1 -BackupFolder C:\temp -NoDbccCheckDb -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -BeNullOrEmpty
            $warn | Should -Match 'Express Edition'
        }

        It "Should restore to another server" {
            $results = Remove-DbaDatabaseSafely -SqlInstance $global:instance2 -Database $db2 -BackupFolder c:\temp -NoDbccCheckDb -Destination $global:instance3
            foreach ($result in $results) {
                $result.SqlInstance | Should -Be $server2.SqlInstance
                $result.TestingInstance | Should -Be $server3.SqlInstance
            }
        }
    }
}
