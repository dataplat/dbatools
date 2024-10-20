$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'ServerProduct', 'Provider', 'DataSource', 'Location', 'ProviderString', 'Catalog', 'SecurityContext', 'SecurityContextRemoteUser', 'SecurityContextRemoteUserPassword', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3

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

    Context "ensure command works" {

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
