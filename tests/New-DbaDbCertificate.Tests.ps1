param($ModuleName = 'dbatools')

Describe "New-DbaDbCertificate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbCertificate
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Subject as a parameter" {
            $CommandUnderTest | Should -HaveParameter Subject
        }
        It "Should have StartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartDate
        }
        It "Should have ExpirationDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExpirationDate
        }
        It "Should have ActiveForServiceBrokerDialog as a parameter" {
            $CommandUnderTest | Should -HaveParameter ActiveForServiceBrokerDialog
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Can create a database certificate" {
        BeforeAll {
            $global:instance1 = $global:instance1 # Assuming this is defined in constants.ps1

            if (-not (Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            }

            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $certificateName1 = "Cert_$(Get-random)"
            $certificateName2 = "Cert_$(Get-random)"
        }

        AfterAll {
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDbMasterKey }
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey }
        }

        It "Successfully creates a new database certificate in default, master database" {
            $cert1 = New-DbaDbCertificate -SqlInstance $global:instance1 -Name $certificateName1
            $cert1.Name | Should -Match $certificateName1
            $cert1 | Remove-DbaDbCertificate
        }

        It "Successfully creates a new database certificate in the tempdb database" {
            $cert2 = New-DbaDbCertificate -SqlInstance $global:instance1 -Name $certificateName2 -Database tempdb
            $cert2.Database | Should -Match "tempdb"
            $cert2 | Remove-DbaDbCertificate
        }
    }
}
