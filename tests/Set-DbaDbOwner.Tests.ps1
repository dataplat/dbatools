#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbOwner",
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
                "ExcludeDatabase",
                "InputObject",
                "TargetLogin",
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

        $svr = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $owner = "dbatoolssci_owner_$(Get-Random)"
        $ownertwo = "dbatoolssci_owner2_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $owner -Password ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $ownertwo -Password ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $dbnametwo = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname -Owner sa
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbnametwo -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname, $dbnametwo
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $owner, $ownertwo

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Should set the database owner" {
        It "Sets the database owner on a specific database" {
            $results = Set-DbaDbOwner -SqlInstance $TestConfig.InstanceSingle -Database $dbName -TargetLogin $owner -OutVariable "global:dbatoolsciOutput"
            $results.Owner | Should -Be $owner
        }
        It "Check it actually set the owner" {
            $svr.Databases[$dbname].refresh()
            $svr.Databases[$dbname].Owner | Should -Be $owner
        }
    }

    Context "Sets multiple database owners" {
        BeforeAll {
            $results = Set-DbaDbOwner -SqlInstance $TestConfig.InstanceSingle -Database $dbName, $dbnametwo -TargetLogin $ownertwo
        }

        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should -Be $ownertwo
            }
        }
        It "Set 2 database owners" {
            $results.Count | Should -Be 2
        }
    }

    Context "Excludes databases" {
        BeforeAll {
            $svr.Databases[$dbName].refresh()
            $results = Set-DbaDbOwner -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbnametwo -TargetLogin $owner
        }

        It "Excludes specified database" {
            $results.Database | Should -Not -Contain $dbnametwo
        }
        It "Updates at least one database" {
            @($results).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context "Enables input from Get-DbaDatabase" {
        BeforeAll {
            $svr.Databases[$dbnametwo].refresh()
            $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbnametwo
            $results = Set-DbaDbOwner -InputObject $db -TargetLogin $owner
        }

        It "Includes specified database" {
            $results.Database | Should -Be $dbnametwo
        }
        It "Sets the database owner on databases" {
            $results.owner | Should -Be $owner
        }
    }

    Context "Sets database owner to sa" {
        BeforeAll {
            $results = Set-DbaDbOwner -SqlInstance $TestConfig.InstanceSingle
        }

        It "Sets the database owner on multiple databases" {
            foreach ($r in $results) {
                $r.owner | Should -Be "sa"
            }
        }
        It "Updates at least one database" {
            @($results).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Owner"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}