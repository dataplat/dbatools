param($ModuleName = 'dbatools')

Describe "Enable-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaDbEncryption
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have EncryptorName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorName
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Force as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
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
            $null = Disable-DbaDbEncryption -SqlInstance $global:instance2 -Database $db.Name
            $results = Enable-DbaDbEncryption -SqlInstance $global:instance2 -EncryptorName $mastercert.Name -Database $db.Name -Force
            $results.EncryptionEnabled | Should -Be $true
        }
    }
}
