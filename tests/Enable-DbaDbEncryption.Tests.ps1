param($ModuleName = 'dbatools')

Describe "Enable-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaDbEncryption
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have EncryptorName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter EncryptorName -Type String -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have Force as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
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

        It "should enable encryption on a database with piping" {
            $results = $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }

        It "should enable encryption on a database" {
            $null = Disable-DbaDbEncryption -SqlInstance $script:instance2 -Database $db.Name
            $results = Enable-DbaDbEncryption -SqlInstance $script:instance2 -EncryptorName $mastercert.Name -Database $db.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }
    }
}
