#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaDbEncryption",
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
                "EncryptorName",
                "EncryptorType",
                "Database",
                "BackupPath",
                "MasterKeySecurePassword",
                "CertificateSubject",
                "CertificateStartDate",
                "CertificateExpirationDate",
                "CertificateActiveForServiceBrokerDialog",
                "BackupSecurePassword",
                "InputObject",
                "AllUserDatabases",
                "Force",
                "Parallel",
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

        # Explain what needs to be set up for the test:
        # To test database encryption, we need multiple test databases.

        # Set variables. They are available in all the It blocks.
        $testDatabases = @()
        1..5 | ForEach-Object {
            $testDatabases += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        if ($testDatabases) {
            $testDatabases | Remove-DbaDatabase
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should mass enable encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $testDatabases.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $backupPath
            }
            $results = Start-DbaDbEncryption @splatEncryption
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -Be 5
            $results | Select-Object -First 1 -ExpandProperty EncryptionEnabled | Should -Be $true
            $results | Select-Object -First 1 -ExpandProperty DatabaseName | Should -Match "random"
        }
    }

    Context "Parallel processing" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $parallelBackupPath = "$($TestConfig.Temp)\$CommandName-Parallel-$(Get-Random)"
            $null = New-Item -Path $parallelBackupPath -ItemType Directory

            $parallelTestDatabases = @()
            1..3 | ForEach-Object {
                $parallelTestDatabases += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parallelTestDatabases) {
                $parallelTestDatabases | Remove-DbaDatabase
            }

            Remove-Item -Path $parallelBackupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "should enable encryption with -Parallel switch" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatParallelEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $parallelTestDatabases.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $parallelBackupPath
                Parallel                = $true
            }
            # Warnings during parallel execution are not catched in $WarnVar as they are in different runspaces
            $results = Start-DbaDbEncryption @splatParallelEncryption
            $WarnVar | Should -BeNullOrEmpty
            $results.Count | Should -Be 3
            foreach ($result in $results) {
                $result.EncryptionEnabled | Should -Be $true
            }
            $results.DatabaseName | Should -Contain $parallelTestDatabases[0].Name
        }
    }

    Context "Output Validation - Sequential Mode" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $seqBackupPath = "$($TestConfig.Temp)\$CommandName-OutputSeq-$(Get-Random)"
            $null = New-Item -Path $seqBackupPath -ItemType Directory

            $seqTestDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatSeqEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $seqTestDatabase.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $seqBackupPath
                EnableException         = $true
            }
            $result = Start-DbaDbEncryption @splatSeqEncryption

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($seqTestDatabase) {
                $seqTestDatabase | Remove-DbaDatabase
            }

            Remove-Item -Path $seqBackupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns SMO Database object in sequential mode" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'EncryptionEnabled'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation - Parallel Mode" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $parBackupPath = "$($TestConfig.Temp)\$CommandName-OutputPar-$(Get-Random)"
            $null = New-Item -Path $parBackupPath -ItemType Directory

            $parTestDatabase = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle

            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splatParEncryption = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Database                = $parTestDatabase.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $parBackupPath
                Parallel                = $true
                EnableException         = $true
            }
            $result = Start-DbaDbEncryption @splatParEncryption

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($parTestDatabase) {
                $parTestDatabase | Remove-DbaDatabase
            }

            Remove-Item -Path $parBackupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject when -Parallel specified" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties for parallel mode" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'DatabaseName',
                'EncryptionEnabled',
                'Status',
                'Error'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in parallel mode output"
            }
        }
    }
}