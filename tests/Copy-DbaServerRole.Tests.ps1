#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaServerRole",
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
                "ServerRole",
                "ExcludeServerRole",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testRoleName = "dbatoolsci_ServerRole_$(Get-Random)"
        $sourceServerConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sourceServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]")
        $sourceServerConn.Query("CREATE SERVER ROLE [$testRoleName]")
        $sourceServerConn.Query("GRANT CONNECT ANY DATABASE TO [$testRoleName]")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serversToCleanup = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
        foreach ($serverInstance in $serversToCleanup) {
            $cleanupServerConn = Connect-DbaInstance -SqlInstance $serverInstance
            $cleanupServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]") | Out-Null
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying server roles" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destServerConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $destServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should successfully copy custom server roles" {
            $splatCopyRole = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $copyResults = Copy-DbaServerRole @splatCopyRole -OutVariable "global:dbatoolsciOutput"
            $copyResults.Name | Should -Be $testRoleName
            $copyResults.Status | Should -Be "Successful"
        }

        It "Should skip existing server roles" {
            $splatFirstCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            Copy-DbaServerRole @splatFirstCopy

            $splatSecondCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $skipResults = Copy-DbaServerRole @splatSecondCopy
            $skipResults.Name | Should -Be $testRoleName
            $skipResults.Status | Should -Be "Skipped"
        }

        It "Should verify server role exists on destination" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            Copy-DbaServerRole @splatCopy

            $splatGetRole = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $roleResults = Get-DbaServerRole @splatGetRole
            $roleResults.Name | Should -Contain $testRoleName
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
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
