#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "ExcludeSystemLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $loginName = "dbatoolsci_comparelogin_$(Get-Random)"

        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $loginName -SecurePassword (ConvertTo-SecureString "Password1234!" -AsPlainText -Force)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $loginName -Confirm:$false -ErrorAction SilentlyContinue
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $loginName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When comparing logins between instances" {
        It "Returns a result with a DestinationOnly login" {
            $result = Compare-DbaLogin -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -Login $loginName
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "DestinationOnly"
        }

        It "Returns correct properties on the result object" {
            $result = Compare-DbaLogin -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -Login $loginName
            $result.LoginName | Should -Be $loginName
            $result.SourceServer | Should -Not -BeNullOrEmpty
            $result.DestinationServer | Should -Not -BeNullOrEmpty
            $result.LoginType | Should -Not -BeNullOrEmpty
        }
    }
}
