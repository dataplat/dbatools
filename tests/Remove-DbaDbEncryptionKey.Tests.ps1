param($ModuleName = 'dbatools')

Describe "Remove-DbaDbEncryptionKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbEncryptionKey
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
            $dbkey = $db | New-DbaDbEncryptionKey -Force
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

        It "should remove encryption key on a database using piping" {
            $results = $dbkey | Remove-DbaDbEncryptionKey
            $results.Status | Should -Be "Success"
            $db.Refresh()
            $db | Get-DbaDbEncryptionKey | Should -BeNullOrEmpty
        }

        It "should remove encryption key on a database" {
            $null = $db | New-DbaDbEncryptionKey -Force
            $results = Remove-DbaDbEncryptionKey -SqlInstance $global:instance2 -Database $db.Name
            $results.Status | Should -Be "Success"
            $db.Refresh()
            $db | Get-DbaDbEncryptionKey | Should -BeNullOrEmpty
        }
    }
}
