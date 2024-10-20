$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EncryptorName', 'EncryptorType', 'Database', 'BackupPath', 'MasterKeySecurePassword', 'CertificateSubject', 'CertificateStartDate', 'CertificateExpirationDate', 'CertificateActiveForServiceBrokerDialog', 'BackupSecurePassword', 'InputObject', 'AllUserDatabases', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $alldbs = @()
        1..5 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $TestConfig.instance2 }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
    }

    Context "Command actually works" {
        It "should mass enable encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $splat = @{
                SqlInstance             = $TestConfig.instance2
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
