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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EncryptorName as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorName
        }
        It "Should have EncryptorType as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorType
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have BackupPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPath
        }
        It "Should have MasterKeySecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterKeySecurePassword
        }
        It "Should have CertificateSubject as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateSubject
        }
        It "Should have CertificateStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateStartDate
        }
        It "Should have CertificateExpirationDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateExpirationDate
        }
        It "Should have CertificateActiveForServiceBrokerDialog as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateActiveForServiceBrokerDialog
        }
        It "Should have BackupSecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupSecurePassword
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have AllUserDatabases as a parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
