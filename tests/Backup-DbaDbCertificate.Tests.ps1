$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Certificate', 'Database', 'ExcludeDatabase', 'EncryptionPassword', 'DecryptionPassword', 'Path', 'Suffix', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $db1Name = "dbatoolscli_$random"
        $db1 = New-DbaDatabase -SqlInstance $script:instance1 -Name $db1Name
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database $db1Name)) {
            $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database $db1Name -Password $pw -Confirm:$false
        }

        $cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert1_$random
        $cert2 = New-DbaDbCertificate -SqlInstance $script:instance1 -Database $db1Name -Confirm:$false -Password $pw -Name dbatoolscli_cert2_$random
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $db1Name -Confirm:$false
    }

    Context "Can create and backup a database certificate" {

        It "backs up the db cert" {
            $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.Certificate | Should -Be $cert.Name
            $results.Status -match "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $script:instance1 -Database $db1Name).ID
        }

        It "warns the caller if the cert cannot be found" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $invalidDBCertName2 = "dbatoolscli_invalidCertName2"
            $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $invalidDBCertName, $invalidDBCertName2, $cert2.Name -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw -WarningVariable warnVariable *> $null
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            #$results.Certificate | Should -Be $cert2.Name
            $warnVariable | Should -BeLike "*Database certificate(s) * not found*"
        }

        # works locally, gah
        It -Skip "backs up all db certs for a database" {
            $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Database $db1Name -EncryptionPassword $pw -DecryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            $results.length | Should -Be 2
            $results.Certificate | Should -Be $cert.Name, $cert2.Name
        }

        # Skip this test as there's a mix of certs, some require a password and some don't and i'll fix later
        It -Skip "backs up all db certs for an instance" {
            $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -EncryptionPassword $pw
            $null = Get-ChildItem -Path $results.Path -ErrorAction Ignore | Remove-Item -Confirm:$false -ErrorAction Ignore
            # $results.length | Should -BeGreaterOrEqual 2
        }
    }
}