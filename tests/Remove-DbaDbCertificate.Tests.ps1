#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbCertificate",
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
                "Database",
                "Certificate",
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

        # Set variables. They are available in all the It blocks.
        # The name has to be unique: New-DbaDbCertificate defaults the name to the database name, so
        # the certificate used to be called "master". A leftover from an earlier run then only made
        # the command warn and return nothing, and the test failed on the empty result instead.
        $certificateName = "dbatoolsci_cert_$(Get-Random)"

        # Create the objects.
        $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master -Name $certificateName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects. The test removes the certificate itself, so this only cleans up
        # after a test that failed before it got that far.
        $splatLeftover = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "master"
            Certificate = $certificateName
            ErrorAction = "SilentlyContinue"
        }
        $null = Get-DbaDbCertificate @splatLeftover | Remove-DbaDbCertificate -ErrorAction SilentlyContinue

        # $PSDefaultParameterValues is the same object in every test file, because they all get it from
        # $TestConfig.Defaults. Leaving EnableException in it makes every later test file in the same
        # process run with EnableException, which turns warnings into terminating errors there.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can remove a database certificate" {
        It "Successfully removes database certificate in master" {
            $results = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master -Certificate $certificateName | Remove-DbaDbCertificate

            $results.Status | Should -Be "Success"
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}