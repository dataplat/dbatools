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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Connection.ManagementConnectionType[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type Microsoft.SqlServer.Management.Smo.Credential
        }
        It "Should have EncryptorName as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorName -Type System.String
        }
        It "Should have EncryptorType as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorType -Type System.String
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[]
        }
        It "Should have BackupPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPath -Type System.String
        }
        It "Should have MasterKeySecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterKeySecurePassword -Type System.Security.SecureString
        }
        It "Should have CertificateSubject as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateSubject -Type System.String
        }
        It "Should have CertificateStartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateStartDate -Type System.DateTime
        }
        It "Should have CertificateExpirationDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateExpirationDate -Type System.DateTime
        }
        It "Should have CertificateActiveForServiceBrokerDialog as a parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateActiveForServiceBrokerDialog -Type System.Management.Automation.SwitchParameter
        }
        It "Should have BackupSecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupSecurePassword -Type System.Security.SecureString
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have AllUserDatabases as a parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
