#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailProfile",
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
                "Profile",
                "ExcludeProfile",
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

        $profilename = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
        $mailProfile = "EXEC msdb.dbo.sysmail_add_profile_sp
            @profile_name='$profilename',
            @description='Profile for system email';"
        $server.Query($mailProfile)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
        $mailProfile = "EXEC msdb.dbo.sysmail_delete_profile_sp
            @profile_name='$profilename';"
        $server.Query($mailProfile)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets DbMail Profile" {
        BeforeAll {
            $results = Get-DbaDbMailProfile -SqlInstance $TestConfig.InstanceMulti1 | Where-Object Name -eq $profilename
            $results2 = Get-DbaDbMailProfile -SqlInstance $server | Where-Object Name -eq $profilename
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Name of $profilename" {
            $results.Name | Should -BeExactly $profilename
        }

        It "Should have Description of 'Profile for system email'" {
            $results.Description | Should -BeExactly "Profile for system email"
        }

        It "Gets results from multiple instances" {
            $results2 | Should -Not -BeNullOrEmpty
            ($results2 | Select-Object SqlInstance -Unique).Count | Should -BeExactly 2
        }
    }

    Context "Gets DbMailProfile when using -Profile" {
        BeforeAll {
            $results = Get-DbaDbMailProfile -SqlInstance $TestConfig.InstanceMulti1 -Profile $profilename
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Name of $profilename" {
            $results.Name | Should -BeExactly $profilename
        }

        It "Should have Description of 'Profile for system email'" {
            $results.Description | Should -BeExactly "Profile for system email"
        }
    }

    Context "Gets no DbMailProfile when using -ExcludeProfile" {
        It "Gets no results" {
            $results = Get-DbaDbMailProfile -SqlInstance $TestConfig.InstanceMulti1 -ExcludeProfile $profilename
            $results.Name | Should -Not -Contain $profilename
        }
    }
}