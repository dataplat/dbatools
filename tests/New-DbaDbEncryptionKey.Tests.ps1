$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException', 'Certificate', 'EncryptionAlgorithm', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
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
        $db | New-DbaDbCertificate
        $db | New-DbaDbEncryptionKey -Force
    }

    AfterAll {
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
        $db | Remove-DbaDatabase
    }

    Context "Command actually works" {
        It "should create a new encryption key" {
            $results = $db | New-DbaDbEncryptionKey -Force -Certificate $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }
}