#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LinkedServer",
                "ServerProduct",
                "Provider",
                "DataSource",
                "Location",
                "ProviderString",
                "Catalog",
                "SecurityContext",
                "SecurityContextRemoteUser",
                "SecurityContextRemoteUserPassword",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $securePassword = ConvertTo-SecureString -String "securePassword!" -AsPlainText -Force
        $loginName = "dbatoolscli_test_$random"
        New-DbaLogin -SqlInstance $instance3 -Login $loginName -SecurePassword $securePassword

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created linked servers.
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS1_$random" -Force -ErrorAction SilentlyContinue
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS2_$random" -Force -ErrorAction SilentlyContinue
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS3_$random" -Force -ErrorAction SilentlyContinue
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS4_$random" -Force -ErrorAction SilentlyContinue
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS5_$random" -Force -ErrorAction SilentlyContinue
        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS6_$random" -Force -ErrorAction SilentlyContinue

        # Cleanup test login.
        Remove-DbaLogin -SqlInstance $instance3 -Login $loginName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "ensure command works" {

        It "Creates a linked server" {
            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS1_$random" -ServerProduct product1 -Provider provider1 -DataSource dataSource1 -Location location1 -ProviderString providerString1 -Catalog catalog1
            $results.Parent.Name | Should -Be $InstanceSingle.Name
            $results.Name | Should -Be "dbatoolscli_LS1_$random"
            $results.ProductName | Should -Be product1
            $results.ProviderName | Should -Be provider1
            $results.DataSource | Should -Be dataSource1
            $results.Location | Should -Be location1
            $results.ProviderString | Should -Be providerString1
            $results.Catalog | Should -Be catalog1
        }

        It "Check the validation for duplicate linked servers" {
            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS1_$random" -WarningVariable warnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*Linked server dbatoolscli_LS1_$random already exists on *"
        }

        It "Check the validation when the linked server param is not provided" {
            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -WarningVariable warnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*LinkedServer is required*"
        }

        It "Creates a linked server using a server from a pipeline" {
            $results = $InstanceSingle | New-DbaLinkedServer -LinkedServer "dbatoolscli_LS2_$random" -ServerProduct product2 -Provider provider2 -DataSource dataSource2 -Location location2 -ProviderString providerString2 -Catalog catalog2
            $results.Parent.Name | Should -Be $InstanceSingle.Name
            $results.Name | Should -Be "dbatoolscli_LS2_$random"
            $results.ProductName | Should -Be product2
            $results.ProviderName | Should -Be provider2
            $results.DataSource | Should -Be dataSource2
            $results.Location | Should -Be location2
            $results.ProviderString | Should -Be providerString2
            $results.Catalog | Should -Be catalog2
        }

        It "Creates a linked server with the different security context options" {
            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS3_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext NoConnection

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -BeNullOrEmpty

            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS4_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext WithoutSecurityContext

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $false

            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS5_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext CurrentSecurityContext

            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $true

            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -BeLike "*SecurityContextRemoteUser is required when SpecifiedSecurityContext is used*"

            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -SecurityContextRemoteUser $loginName -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -BeLike "*SecurityContextRemoteUserPassword is required when SpecifiedSecurityContext is used*"

            $results = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer "dbatoolscli_LS6_$random" -ServerProduct mssql -Provider sqlncli -DataSource $instance3 -SecurityContext SpecifiedSecurityContext -SecurityContextRemoteUser $loginName -SecurityContextRemoteUserPassword $securePassword

            $results.RemoteUser | Should -Be $loginName
            $results.Impersonate | Should -Be $false
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputTestLsName = "dbatoolscli_LSOutput_$random"
            $result = New-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer $outputTestLsName -ServerProduct "outputProduct" -Provider "outputProvider" -DataSource "outputDataSource"
        }
        AfterAll {
            Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer $outputTestLsName -Force -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.LinkedServer"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "RemoteServer",
                "ProductName",
                "Impersonate",
                "RemoteUser",
                "Publisher",
                "Distributor",
                "DateLastModified"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["RemoteServer"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["RemoteServer"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["Publisher"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Publisher"].MemberType | Should -Be "AliasProperty"
        }
    }
}