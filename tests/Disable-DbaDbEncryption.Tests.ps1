param($ModuleName = 'dbatools')

Describe "Disable-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaDbEncryption
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "NoEncryptionKeyDrop",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $PSDefaultParameterValues["*:Confirm"] = $false
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $masterkey = Get-DbaDbMasterKey -SqlInstance $global:instance2 -Database master
            if (-not $masterkey) {
                $delmasterkey = $true
                $masterkey = New-DbaServiceMasterKey -SqlInstance $global:instance2 -SecurePassword $passwd
            }
            $mastercert = Get-DbaDbCertificate -SqlInstance $global:instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $mastercert) {
                $delmastercert = $true
                $mastercert = New-DbaDbCertificate -SqlInstance $global:instance2
            }

            $db = New-DbaDatabase -SqlInstance $global:instance2
            $db | New-DbaDbMasterKey -SecurePassword $passwd
            $db | New-DbaDbCertificate
            $db | New-DbaDbEncryptionKey -Force
            $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
        }

        AfterAll {
            if ($db) {
                $db | Remove-DbaDatabase
            }
            if ($delmastercert) {
                $mastercert | Remove-DbaDbCertificate
            }
            if ($delmasterkey) {
                $masterkey | Remove-DbaDbMasterKey
            }
        }

        It "should disable encryption on a database with piping" {
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = $db | Disable-DbaDbEncryption -NoEncryptionKeyDrop
            $results.EncryptionEnabled | Should -Be $false
        }

        It "should disable encryption on a database" {
            $null = $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = Disable-DbaDbEncryption -SqlInstance $global:instance2 -Database $db.Name
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}
