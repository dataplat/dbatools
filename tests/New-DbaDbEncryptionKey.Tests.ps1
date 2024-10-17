param($ModuleName = 'dbatools')

Describe "New-DbaDbEncryptionKey Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbEncryptionKey
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have EncryptorName parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptorName -Type String -Not -Mandatory
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have EncryptionAlgorithm parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptionAlgorithm -Type String -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "New-DbaDbEncryptionKey Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential "sqladmin", $passwd

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

    Context "Command actually works" {
        It "should create a new encryption key using piping" {
            $results = $db | New-DbaDbEncryptionKey -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
        It "should create a new encryption key" {
            $null = Get-DbaDbEncryptionKey -SqlInstance $global:instance2 -Database $db.Name | Remove-DbaDbEncryptionKey
            $results = New-DbaDbEncryptionKey -SqlInstance $global:instance2 -Database $db.Name -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }
}

Describe "New-DbaDbEncryptionKey Integration Tests for Async" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterkey = Get-DbaDbMasterKey -SqlInstance $global:instance2 -Database master
        if (-not $masterkey) {
            $delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $global:instance2 -SecurePassword $passwd
        }

        $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $global:instance2 -Database master

        if (-not $masterasym) {
            $delmasterasym = $true
            $masterasym = New-DbaDbAsymmetricKey -SqlInstance $global:instance2 -Database master
        }

        $db = New-DbaDatabase -SqlInstance $global:instance2
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbAsymmetricKey
    }

    AfterAll {
        if ($db) {
            $db | Remove-DbaDatabase
        }
        if ($delmasterasym) {
            $masterasym | Remove-DbaDbAsymmetricKey
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
    }

    Context "Command does not work but warns" {
        It "should warn that it can't create an encryption key" -Skip {
            $warn = $null
            $null = $db | New-DbaDbEncryptionKey -Force -Type AsymmetricKey -EncryptorName $masterasym.Name -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Match "n order to encrypt the database encryption key with an as"
        }
    }
}
