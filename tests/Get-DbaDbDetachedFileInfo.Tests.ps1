#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDetachedFileInfo",
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
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $versionName = $server.GetSqlServerVersionName()
        $random = Get-Random
        $dbname = "dbatoolsci_detatch_$random"
        $server.Query("CREATE DATABASE $dbname")
        $path = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Where-Object PhysicalName -like "*.mdf").PhysicalName
        Detach-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Force
    }

    AfterAll {
        $server.Query("CREATE DATABASE $dbname
            ON (FILENAME = '$path')
            FOR ATTACH")
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $TestConfig.InstanceSingle -Path $path -OutVariable "global:dbatoolsciOutput"
        }

        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be created database" {
            $results.Name | Should -Be $dbname
        }

        It "Should be the correct version" {
            $results.Version | Should -Be $versionName
        }

        It "Should have Data files" {
            $results.DataFiles | Should -Not -BeNullOrEmpty
        }

        It "Should have Log files" {
            $results.LogFiles | Should -Not -BeNullOrEmpty
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
                "Name",
                "Version",
                "ExactVersion",
                "Collation",
                "DataFiles",
                "LogFiles"
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