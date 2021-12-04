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
        $pw = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb)) {
            $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $pw -Confirm:$false
        }
    }
    AfterAll {
        Get-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb | Remove-DbaDbCertificate -Confirm:$false
        Get-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb | Remove-DbaDbMasterKey -Confirm:$false
    }

    Context "Can create and backup a database certificate" {
        $cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -Confirm:$false -Password $pw -Name cert1
        $cert2 = New-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -Confirm:$false -Password $pw -Name cert2
        $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Name -Database tempdb -EncryptionPassword $pw -DecryptionPassword $pw
        $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

        It "backs up the db cert" {
            $results.Certificate | Should -Be $cert.Name
            $results.Status -match "Success"
        }

        It "warns the caller if the cert cannot be found" {
            $invalidDBCertName = "dbatoolscli_invalidCertName"
            $results = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $invalidDBCertName, $cert2.Name -Database tempdb -EncryptionPassword $pw -DecryptionPassword $pw -WarningVariable warnVariable
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
            $results.Certificate | Should -Be $cert2.Name
            $warnVariable | Should -BeLike "*Database certificate $invalidDBCertName was not found*"
        }
    }
}