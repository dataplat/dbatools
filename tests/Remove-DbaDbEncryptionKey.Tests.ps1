param($ModuleName = 'dbatools')

Describe "Remove-DbaDbEncryptionKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbEncryptionKey
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
