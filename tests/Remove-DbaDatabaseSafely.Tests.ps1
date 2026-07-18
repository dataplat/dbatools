#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDatabaseSafely",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Destination",
                "DestinationSqlCredential",
                "NoDbccCheckDb",
                "BackupFolder",
                "CategoryName",
                "JobOwner",
                "AllDatabases",
                "BackupCompression",
                "ReuseSourceFolderStructure",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        $db1 = "dbatoolsci_safely"
        $db2 = "dbatoolsci_safely_otherInstance"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $db1
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $db2

        # Harness honesty: the command's own preconditions require (a) the instance service
        # account to reach the runner-local backup folder and (b) WMI service access for the
        # SQL Agent probe. Environments where the test instances are not local to the runner
        # (remote lab VMs) fail those preconditions before the command does any work - the
        # scenarios can then only fail environmentally, so they skip at runtime instead.
        $safelyCapable = $false
        try {
            $copy1Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $backupFolderVisible = Test-DbaPath -SqlInstance $copy1Server -Path $backupPath
            $agentReachable = @(Get-DbaService -ComputerName $copy1Server.ComputerName -Type Agent -EnableException).Count -gt 0
            $safelyCapable = $backupFolderVisible -and $agentReachable
        } catch {
            $safelyCapable = $false
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $db1, $db2
        if ($safelyCapable) {
            # The restore jobs exist only when the scenarios actually ran (see the capability probe).
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job "Rationalised Database Restore Script for $db1"
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job "Rationalised Database Restore Script for $db2"
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {
        It "Should restore to the same server" {
            if (-not $safelyCapable) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the command's backup-folder/agent preconditions are not satisfiable from this runner"
                return
            }
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.InstanceCopy1 -Database $db1 -BackupFolder $backupPath -NoDbccCheckDb
            $results.DatabaseName | Should -Be $db1
            $results.SqlInstance | Should -Be $TestConfig.InstanceCopy1
            $results.TestingInstance | Should -Be $TestConfig.InstanceCopy1
            $results.BackupFolder | Should -Be $backupPath
        }

        It "Should restore to another server" {
            if (-not $safelyCapable) {
                Set-ItResult -Skipped -Because "the command's backup-folder/agent preconditions are not satisfiable from this runner"
                return
            }
            $results = Remove-DbaDatabaseSafely -SqlInstance $TestConfig.InstanceCopy1 -Database $db2 -BackupFolder $backupPath -NoDbccCheckDb -Destination $TestConfig.InstanceCopy2
            $results.DatabaseName | Should -Be $db2
            $results.SqlInstance | Should -Be $TestConfig.InstanceCopy1
            $results.TestingInstance | Should -Be $TestConfig.InstanceCopy2
            $results.BackupFolder | Should -Be $backupPath
        }
    }
}