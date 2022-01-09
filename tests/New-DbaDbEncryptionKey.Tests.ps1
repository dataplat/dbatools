$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException', 'EncryptorName', 'EncryptionAlgorithm', 'Force', 'Type'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential "sqladmin", $passwd

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
    }

    AfterAll {
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
        if ($db) {
            $db | Remove-DbaDatabase
        }
    }

    Context "Command actually works" {
        It "should create a new encryption key using piping" {
            $results = $db | New-DbaDbEncryptionKey -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
        It "should create a new encryption key" {
            $null = Get-DbaDbEncryptionKey -SqlInstance $script:instance2 -Database $db.Name | Remove-DbaDbEncryptionKey
            $results = New-DbaDbEncryptionKey -SqlInstance $script:instance2 -Database $db.Name -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }
}



Describe "$CommandName Integration Tests for Async" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterkey = Get-DbaDbMasterKey -SqlInstance $script:instance2 -Database master
        if (-not $masterkey) {
            $delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $script:instance2 -SecurePassword $passwd
        }

        $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database master

        if (-not $masterasym) {
            $delmasterasym = $true
            $masterasym = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database master
        }

        $db = New-DbaDatabase -SqlInstance $script:instance2
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbAsymmetricKey
    }

    AfterAll {
        if ($delmasterasym) {
            $masterasym | Remove-DbaDbAsymmetricKey
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
        if ($db) {
            $db | Remove-DbaDatabase
        }
    }

    # In order to encrypt the database encryption key with an asymmetric
#key, please use an asymmetric key that resides on an extensible key management provider

    Context "Command does not work but warns" {
        It "should warn that it cant create an encryption key" {
            $null = $db | New-DbaDbEncryptionKey -Force -Type AsymmetricKey -EncryptorName $masterasym.Name -WarningVariable warn
            $warn | Should -Match "n order to encrypt the database encryption key with an as"
        }
    }
}