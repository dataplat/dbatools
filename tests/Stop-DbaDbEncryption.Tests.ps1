param($ModuleName = 'dbatools')

Describe "Stop-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaDbEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $PSDefaultParameterValues["*:Confirm"] = $false
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $masterkey = Get-DbaDbMasterKey -SqlInstance $script:instance2 -Database master
            if (-not $masterkey) {
                $delmasterkey = $true
                $masterkey = New-DbaServiceMasterKey -SqlInstance $script:instance2 -SecurePassword $passwd
            }
            $mastercert = Get-DbaDbCertificate -SqlInstance $script:instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $mastercert) {
                $delmastercert = $true
                $mastercert = New-DbaDbCertificate -SqlInstance $script:instance2
            }

            $db = New-DbaDatabase -SqlInstance $script:instance2
            $db | New-DbaDbMasterKey -SecurePassword $passwd
            $db | New-DbaDbCertificate
            $db | New-DbaDbEncryptionKey -Force
            $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force

            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
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

        It "should disable encryption on a database" {
            $results = Stop-DbaDbEncryption -SqlInstance $script:instance2
            $results | ForEach-Object {
                $_.EncryptionEnabled | Should -Be $false
            }
        }
    }
}
