#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLoginPassword",
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
                "Login",
                "Dictionary",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $weaksauce = "dbatoolsci_testweak"
        $weakpass = ConvertTo-SecureString $weaksauce -AsPlainText -Force
        $newlogin = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $weaksauce -HashedPassword (Get-PasswordHash $weakpass $server.VersionMajor) -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $newlogin.Drop()
        } catch {
            # don't care
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "making sure command works" {
        It "finds the new weak password and supports piping" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle | Test-DbaLoginPassword -OutVariable "global:dbatoolsciOutput"
            $results.SqlLogin | Should -Contain $weaksauce
        }
        It "returns just one login" {
            $results = Test-DbaLoginPassword -SqlInstance $TestConfig.InstanceSingle -Login $weaksauce
            $results.SqlLogin | Should -Be $weaksauce
        }
        It "handles passwords with quotes, see #9095" {
            $results = Test-DbaLoginPassword -SqlInstance $TestConfig.InstanceSingle -Login $weaksauce -Dictionary "&é`"'(-", "hello"
            $results.SqlLogin | Should -Be $weaksauce
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a DataRow" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SqlLogin",
                "WeakPassword",
                "Password",
                "Disabled",
                "CreatedDate",
                "ModifiedDate",
                "DefaultDatabase"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            foreach ($prop in $expectedProperties) {
                $prop | Should -BeIn $actualProperties
            }
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}