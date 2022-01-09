$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'
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
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbCertificate
        $dbkey = $db | New-DbaDbEncryptionKey -Force
    }

    AfterAll {
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
        if ($db) {
            $db | Remove-DbaDatabase
        }
    }

    Context "Command actually works" {
        It "should remove encryption key on a database using piping" {
            $results = $dbkey | Remove-DbaDbEncryptionKey
            $results.Status | Should -Be "Success"
            $db.Refresh()
            $db | Get-DbaDbEncryptionKey | Should -Be $null
        }
        It "should remove encryption key on a database" {
            $null = $db | New-DbaDbEncryptionKey -Force
            $results = Remove-DbaDbEncryptionKey -SqlInstance $script:instance2 -Database $db.Name
            $results.Status | Should -Be "Success"
            $db.Refresh()
            $db | Get-DbaDbEncryptionKey | Should -Be $null
        }
    }
}