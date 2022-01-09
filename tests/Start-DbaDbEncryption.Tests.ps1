$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EncryptorName', 'EncryptorType', 'Database', 'BackupPath', 'MasterKeySecurePassword', 'CertificateSubject', 'CertificateStartDate', 'CertificateExpirationDate', 'CertificateActiveForServiceBrokerDialog', 'CertificateSecurePassword', 'InputObject', 'Force', 'All', 'EnableException'
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
        1..5 | ForEach-Object { $alldbs += New-DbaDatabase -SqlInstance $script:instance2 }
    }

    AfterAll {
        if ($alldbs) {
            $alldbs | Remove-DbaDatabase
        }
    }

    Context "Command actually works" {
        It "should mass enable encryption" {
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $params = @{
                All                       = $true
                Force                     = $true
                MasterKeySecurePassword   = $passwd
                CertificateSecurePassword = $passwd
                BackupPath                = "C:\temp"
                EnableException           = $true
            }
            $results = Start-DbaDbEncryption -SqlInstance $script:instance2 -All -Force -MasterKeySecurePassword $passwd -CertificateSecurePassword $passwd -BackupPath "C:\temp"
        }
    }
}