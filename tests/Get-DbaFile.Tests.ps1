#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFile",
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
                "FileType",
                "Depth",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns some files" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $random = Get-Random
            $testDbName = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $testDbName")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find the new database file" {
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            ($results.Filename -match "dbatoolsci").Count | Should -BeGreaterThan 0
        }

        It "Should find the new database log file" {
            $logPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle).Log
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $logPath
            ($results.Filename -like "*dbatoolsci*ldf").Count | Should -BeGreaterThan 0
        }

        It "Should find the master database file" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $masterPath = $server.MasterDBPath
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $masterPath
            ($results.Filename -match "master.mdf").Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Filename",
                "RemoteFilename"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "SqlInstance",
                "Filename"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}