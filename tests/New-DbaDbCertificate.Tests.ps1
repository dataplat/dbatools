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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[]
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Subject as a parameter" {
            $CommandUnderTest | Should -HaveParameter Subject -Type String[]
        }
        It "Should have StartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartDate -Type DateTime
        }
        It "Should have ExpirationDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExpirationDate -Type DateTime
        }
        It "Should have ActiveForServiceBrokerDialog as a parameter" {
            $CommandUnderTest | Should -HaveParameter ActiveForServiceBrokerDialog -Type Switch
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Can create a database certificate" {
        BeforeAll {
            $env:instance1 = $env:instance1 # Assuming this is defined in constants.ps1

            if (-not (Get-DbaDbMasterKey -SqlInstance $env:instance1 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $env:instance1 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $env:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $certificateName1 = "Cert_$(Get-random)"
            $certificateName2 = "Cert_$(Get-random)"
        }

        AfterAll {
            if ($tempdbmasterkey) { $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false }
            if ($masterKey) { $masterkey | Remove-DbaDbMasterKey -Confirm:$false }
        }

        It "Successfully creates a new database certificate in default, master database" {
            $cert1 = New-DbaDbCertificate -SqlInstance $env:instance1 -Name $certificateName1 -Confirm:$false
            $cert1.Name | Should -Match $certificateName1
            $cert1 | Remove-DbaDbCertificate -Confirm:$false
        }

        It "Successfully creates a new database certificate in the tempdb database" {
            $cert2 = New-DbaDbCertificate -SqlInstance $env:instance1 -Name $certificateName2 -Database tempdb -Confirm:$false
            $cert2.Database | Should -Match "tempdb"
            $cert2 | Remove-DbaDbCertificate -Confirm:$false
        }
    }
}
