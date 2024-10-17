param($ModuleName = 'dbatools')

Describe "Get-DbaDbCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbCertificate
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Not -Mandatory
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type Object[] -Not -Mandatory
        }
        It "Should have Subject as a parameter" {
            $CommandUnderTest | Should -HaveParameter Subject -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Can get a database certificate" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"

            if (-not (Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $cert1 = New-DbaDbCertificate -SqlInstance $global:instance1 -Name $certificateName1 -Confirm:$false
            $cert2 = New-DbaDbCertificate -SqlInstance $global:instance1 -Name $certificateName2 -Database "tempdb" -Confirm:$false
        }

        AfterAll {
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }
        }

        It "returns database certificate created in default, master database" {
            $cert = Get-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $certificateName1
            $cert.Database | Should -Match 'master'
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database master).Id
        }

        It "returns database certificate created in tempdb database, looked up by certificate name" {
            $cert = Get-DbaDbCertificate -SqlInstance $global:instance1 -Database tempdb
            $cert.Name | Should -Match $certificateName2
            $cert.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb).Id
        }

        It "returns database certificates excluding those in the master database" {
            $cert = Get-DbaDbCertificate -SqlInstance $global:instance1 -ExcludeDatabase master
            $cert.Database | Should -Not -Match 'master'
        }
    }
}
