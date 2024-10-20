$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Certificate', 'Subject', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can get a database certificate" {
        BeforeAll {
            if (-not (Get-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $cert1 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Name $certificateName1 -Confirm:$false
            $cert2 = New-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Name $certificateName2 -Database "tempdb" -Confirm:$false
        }
        AfterAll {
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }
        }

        $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Certificate $certificateName1
        It "returns database certificate created in default, master database" {
            "$($cert.Database)" -match 'master' | Should Be $true
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master).Id
        }

        $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -Database tempdb
        It "returns database certificate created in tempdb database, looked up by certificate name" {
            "$($cert.Name)" -match $certificateName2 | Should Be $true
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb).Id
        }

        $cert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance1 -ExcludeDatabase master
        It "returns database certificates excluding those in the master database" {
            "$($cert.Database)" -notmatch 'master' | Should Be $true
        }

    }
}
