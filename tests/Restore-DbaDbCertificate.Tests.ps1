$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'EncryptionPassword', 'Database', 'DecryptionPassword', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $password = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force
            $cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -Confirm:$false
            $backup = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -EncryptionPassword $password -Confirm:$false
            $cert | Remove-DbaDbCertificate -Confirm:$false
        }
        AfterEach {
            $null = Remove-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Name -Database tempdb -Confirm:$false
        }
        AfterAll {
            $null = $masterkey | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "restores the db cert when passing in a .cer file" {
            $results = Restore-DbaDbCertificate -SqlInstance $script:instance1 -Path $backup.ExportPath -Password $password -Database tempdb -EncryptionPassword $password -Confirm:$false
            $results.Parent.Name | Should Be 'tempdb'
            $results.Name | Should Not BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should Be "Password"
            $results | Remove-DbaDbCertificate -Confirm:$false
            # TODO: Create a test for password generated cert
            # From what I can tell, what matters is creation, not restore.
        }

        It "restores the db cert when passing in a folder" {
            $folder = split-path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $script:instance1 -Path $folder -Password $password -Database tempdb -EncryptionPassword $password -Confirm:$false
            $results.Parent.Name | Should Be 'tempdb'
            $results.Name | Should Not BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should Be "Password"
            $results | Remove-DbaDbCertificate -Confirm:$false
        }

        It "restores the db cert and encrypts with master key" {
            $folder = split-path $backup.ExportPath -Parent
            $results = Restore-DbaDbCertificate -SqlInstance $script:instance1 -Path $folder -Password $password -Database tempdb -Confirm:$false
            $results.Parent.Name | Should Be 'tempdb'
            $results.Name | Should Not BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should Be "MasterKey"
            $results | Remove-DbaDbCertificate -Confirm:$false
        }
    }
}