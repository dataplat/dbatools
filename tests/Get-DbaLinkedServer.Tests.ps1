#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLinkedServer",
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
                "ExcludeLinkedServer",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $null = $server.Query("EXEC master.dbo.sp_addlinkedserver
            @server = N'$($TestConfig.InstanceMulti2)',
            @srvproduct=N'SQL Server' ;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("EXEC master.dbo.sp_dropserver '$($TestConfig.InstanceMulti2)', 'droplogins';  ")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Linked Servers" {
        BeforeAll {
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceMulti1 | Where-Object Name -eq $TestConfig.InstanceMulti2
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Remote Server of $($TestConfig.InstanceMulti2)" {
            $results.RemoteServer | Should -Be $TestConfig.InstanceMulti2
        }

        It "Should have a product name of SQL Server" {
            $results.productname | Should -Be "SQL Server"
        }

        It "Should have Impersonate for authentication" {
            $results.Impersonate | Should -Be $true
        }
    }

    Context "Gets Linked Servers using -LinkedServer" {
        BeforeAll {
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceMulti1 -LinkedServer $TestConfig.InstanceMulti2
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Remote Server of $($TestConfig.InstanceMulti2)" {
            $results.RemoteServer | Should -Be $TestConfig.InstanceMulti2
        }

        It "Should have a product name of SQL Server" {
            $results.productname | Should -Be "SQL Server"
        }

        It "Should have Impersonate for authentication" {
            $results.Impersonate | Should -Be $true
        }
    }

    Context "Gets Linked Servers using -ExcludeLinkedServer" {
        It "Gets results" {
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceMulti1 -ExcludeLinkedServer $TestConfig.InstanceMulti2
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceMulti1 -LinkedServer $TestConfig.InstanceMulti2
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
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

        It "Has valid values for standard connection properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
            $result[0].InstanceName | Should -Not -BeNullOrEmpty
            $result[0].SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}