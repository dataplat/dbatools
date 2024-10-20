$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException', 'NoEncryptionKeyDrop'
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
        $masterkey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterkey) {
            $delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $passwd
        }
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbCertificate
        $db | New-DbaDbEncryptionKey -Force
        $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
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
        It "should disable encryption on a database with piping" {
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = $db | Disable-DbaDbEncryption -NoEncryptionKeyDrop -WarningVariable warn 3> $null
            $warn | Should -Be $null
            $results.EncryptionEnabled | Should -Be $false
        }
        It "should disable encryption on a database" {
            $null = $db | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            # Give it time to finish encrypting or it'll error
            Start-Sleep 10
            $results = Disable-DbaDbEncryption -SqlInstance $TestConfig.instance2 -Database $db.Name -WarningVariable warn 3> $null
            $warn | Should -Be $null
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}
