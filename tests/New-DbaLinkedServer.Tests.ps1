param($ModuleName = 'dbatools')

Describe "New-DbaLinkedServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
        $instance3 = Connect-DbaInstance -SqlInstance $global:instance3

        $securePassword = ConvertTo-SecureString -String 'securePassword!' -AsPlainText -Force
        $loginName = "dbatoolscli_test_$random"
        New-DbaLogin -SqlInstance $instance3 -Login $loginName -SecurePassword $securePassword
    }

    AfterAll {
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS1_$random" -Confirm:$false -Force
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS2_$random" -Confirm:$false -Force
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS3_$random" -Confirm:$false -Force
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS4_$random" -Confirm:$false -Force
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS5_$random" -Confirm:$false -Force
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS6_$random" -Confirm:$false -Force

        Remove-DbaLogin -SqlInstance $instance3 -Login $loginName -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaLinkedServer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have LinkedServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter LinkedServer -Type System.String
        }
        It "Should have ServerProduct as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerProduct -Type System.String
        }
        It "Should have Provider as a parameter" {
            $CommandUnderTest | Should -HaveParameter Provider -Type System.String
        }
        It "Should have DataSource as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataSource -Type System.String
        }
        It "Should have Location as a parameter" {
            $CommandUnderTest | Should -HaveParameter Location -Type System.String
        }
        It "Should have ProviderString as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProviderString -Type System.String
        }
        It "Should have Catalog as a parameter" {
            $CommandUnderTest | Should -HaveParameter Catalog -Type System.String
        }
        It "Should have SecurityContext as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurityContext -Type System.String
        }
        It "Should have SecurityContextRemoteUser as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurityContextRemoteUser -Type System.String
        }
        It "Should have SecurityContextRemoteUserPassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurityContextRemoteUserPassword -Type System.Security.SecureString
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Server[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        It "Creates a linked server" {
            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS1_$random" -ServerProduct product1 -Provider provider1 -DataSource dataSource1 -Location location1 -ProviderString providerString1 -Catalog catalog1
            $results.Parent.Name | Should -Be $instance2.Name
            $results.Name | Should -Be "dbatoolscli_LS1_$random"
            $results.ProductName | Should -Be product1
            $results.ProviderName | Should -Be provider1
            $results.DataSource | Should -Be dataSource1
            $results.Location | Should -Be location1
            $results.ProviderString | Should -Be providerString1
            $results.Catalog | Should -Be catalog1
        }

        It "Check the validation for duplicate linked servers" {
            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS1_$random" -WarningVariable warnings
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*Linked server dbatoolscli_LS1_$random already exists on *"
        }

        It "Check the validation when the linked server param is not provided" {
            $results = New-DbaLinkedServer -SqlInstance $instance2 -WarningVariable warnings
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*LinkedServer is required*"
        }

        It "Creates a linked server using a server from a pipeline" {
            $results = $instance2 | New-DbaLinkedServer -LinkedServer "dbatoolscli_LS2_$random" -ServerProduct product2 -Provider provider2 -DataSource dataSource2 -Location location2 -ProviderString providerString2 -Catalog catalog2
            $results.Parent.Name | Should -Be $instance2.Name
            $results.Name | Should -Be "dbatoolscli_LS2_$random"
            $results.ProductName | Should -Be product2
            $results.ProviderName | Should -Be provider2
            $results.DataSource | Should -Be dataSource2
            $results.Location | Should -Be location2
            $results.ProviderString | Should -Be providerString2
            $results.Catalog | Should -Be catalog2
        }

        It "Creates a linked server with the different security context options" {
            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS3_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext NoConnection

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -BeNullOrEmpty

            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS4_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext WithoutSecurityContext

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $false

            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS5_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext CurrentSecurityContext

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $true

            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -WarningVariable warnings

            $warnings | Should -BeLike "*SecurityContextRemoteUser is required when SpecifiedSecurityContext is used*"

            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -SecurityContextRemoteUser $loginName -WarningVariable warnings

            $warnings | Should -BeLike "*SecurityContextRemoteUserPassword is required when SpecifiedSecurityContext is used*"

            $results = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -SecurityContextRemoteUser $loginName -SecurityContextRemoteUserPassword $securePassword

            $results.RemoteUser | Should -Be $loginName
            $results.Impersonate | Should -Be $false
        }
    }
}
