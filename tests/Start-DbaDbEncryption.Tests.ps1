param($ModuleName = 'dbatools')

Describe "Start-DbaDbEncryption" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $PSDefaultParameterValues["*:Confirm"] = $false
        $alldbs = @()
        1..5 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $global:instance2 }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaDbEncryption
        }

        $params = @(
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
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        It "should mass enable encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splat = @{
                SqlInstance             = $global:instance2
                Database                = $alldbs.Name
                MasterKeySecurePassword = $passwd
                BackupSecurePassword    = $passwd
                BackupPath              = "C:\temp"
            }
            $results = Start-DbaDbEncryption @splat -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results.Count | Should -Be 5
            $results | Select-Object -First 1 -ExpandProperty EncryptionEnabled | Should -Be $true
            $results | Select-Object -First 1 -ExpandProperty DatabaseName | Should -Match "random"
        }
    }
}
