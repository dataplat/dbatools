param($ModuleName = 'dbatools')

Describe "Get-DbaDbEncryptionKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbEncryptionKey
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Mandatory:$false
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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

        It "should get an encryption key on a database using piping" {
            $results = $db | Get-DbaDbEncryptionKey
            $results.EncryptionType | Should -Be "ServerCertificate"
        }

        It "should get an encryption key on a database" {
            $results = Get-DbaDbEncryptionKey -SqlInstance $global:instance2 -Database $db.Name
            $results.EncryptionType | Should -Be "ServerCertificate"
        }
    }
}
