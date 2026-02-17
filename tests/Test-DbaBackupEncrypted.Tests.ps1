#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaBackupEncrypted",
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
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false

        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory

        $alldbs = @()
        1..2 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
        Remove-Item -Path $backupPath -Recurse
        # TODO: Should be refactored next to only remove the created databases.
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeSystem | Remove-DbaDatabase
    }

    Context "Command actually works" {
        It "should detect encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splat = @{
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = $backupPath
                EnableException         = $true
            }
            $null = $alldbs | Start-DbaDbEncryption @splat
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path $backupPath
            $results = $backups | Test-DbaBackupEncrypted -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results.Encrypted | Should -Be $true
        }
        It "should detect encryption from piped file" {
            $backups = $alldbs | Select-Object -First 1 | Backup-DbaDatabase -Path $backupPath
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.InstanceSingle -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $true
        }

        It "should say a non-encryted file is not encrypted" {
            $backups = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Backup-DbaDatabase -Path $backupPath
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.InstanceSingle -FilePath $backups.BackupPath
            $results.Encrypted | Should -Be $false
        }

        It "should say a non-encryted file is not encrypted" {
            $encryptor = (Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master | Where-Object Name -notmatch "#" | Select-Object -First 1).Name
            $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $backup = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Path $backupPath -EncryptionAlgorithm AES192 -EncryptionCertificate $encryptor -Database $db.Name
            $results = Test-DbaBackupEncrypted -SqlInstance $TestConfig.InstanceSingle -FilePath $backup.BackupPath
            $results.Encrypted | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "FilePath",
                "BackupName",
                "Encrypted",
                "KeyAlgorithm",
                "EncryptorThumbprint",
                "EncryptorType",
                "TDEThumbprint",
                "Compressed"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}