$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException', 'ExcludeDatabase'
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
        It "should get an encryption key on a database using piping" {
            $results = $db | Get-DbaDbEncryptionKey
            $results.EncryptionType | Should -Be "ServerCertificate"
        }
        It "should get an encryption key on a database" {
            $results = Get-DbaDbEncryptionKey -SqlInstance $TestConfig.instance2 -Database $db.Name
            $results.EncryptionType | Should -Be "ServerCertificate"
        }
    }
}
