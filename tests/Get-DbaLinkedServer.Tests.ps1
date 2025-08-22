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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("EXEC master.dbo.sp_addlinkedserver
            @server = N'$($TestConfig.instance3)',
            @srvproduct=N'SQL Server' ;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("EXEC master.dbo.sp_dropserver '$($TestConfig.instance3)', 'droplogins';  ")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Linked Servers" {
        BeforeAll {
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.instance2 | Where-Object Name -eq $TestConfig.instance3
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Remote Server of $($TestConfig.instance3)" {
            $results.RemoteServer | Should -Be $TestConfig.instance3
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
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.instance2 -LinkedServer $TestConfig.instance3
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Remote Server of $($TestConfig.instance3)" {
            $results.RemoteServer | Should -Be $TestConfig.instance3
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
            $results = Get-DbaLinkedServer -SqlInstance $TestConfig.instance2 -ExcludeLinkedServer $TestConfig.instance3
            $results | Should -BeNullOrEmpty
        }
    }
}