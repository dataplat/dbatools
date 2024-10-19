param($ModuleName = 'dbatools')

Describe "New-DbaDbMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbMasterKey
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "Database",
                "SecurePassword",
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
            $masterkey = Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database master
            if (-not $masterkey) {
                $delmasterkey = $true
                $masterkey = New-DbaServiceMasterKey -SqlInstance $global:instance1 -SecurePassword $passwd
            }
            $mastercert = Get-DbaDbCertificate -SqlInstance $global:instance1 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
            if (-not $mastercert) {
                $delmastercert = $true
                $mastercert = New-DbaDbCertificate -SqlInstance $global:instance1
            }
            $db = New-DbaDatabase -SqlInstance $global:instance1
            $db1 = New-DbaDatabase -SqlInstance $global:instance1
        }

        AfterAll {
            if ($db) {
                $db | Remove-DbaDatabase
            }
            if ($db1) {
                $db1 | Remove-DbaDatabase
            }
            if ($delmastercert) {
                $mastercert | Remove-DbaDbCertificate
            }
            if ($delmasterkey) {
                $masterkey | Remove-DbaMasterKey
            }
        }

        It "should create master key on a database using piping" {
            $PSDefaultParameterValues["*:Confirm"] = $false
            $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
            $results = $db | New-DbaDbMasterKey -SecurePassword $passwd
            $results.IsEncryptedByServer | Should -Be $true
        }

        It "should create master key on a database" {
            $results = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database $db1.Name -SecurePassword $passwd
            $results.IsEncryptedByServer | Should -Be $true
        }
    }
}
