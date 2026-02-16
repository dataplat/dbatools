#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentProxy",
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
                "ProxyAccount",
                "ExcludeProxyAccount",
                "Force",
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

        # Set up test proxy on source instance
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $sourceServer.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_proxy  @proxy_name = 'dbatoolsci_agentproxy', @enabled = 1, @credential_name = 'dbatoolsci_credential'"
        $sourceServer.Query($sql)

        # Set up credential on destination instance
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $sql = "CREATE CREDENTIAL dbatoolsci_credential WITH IDENTITY = 'sa', SECRET = 'dbatools'"
        $destServer.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up source instance
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $sourceServer.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $sourceServer.Query($sql)

        # Clean up destination instance
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $sql = "EXEC msdb.dbo.sp_delete_proxy @proxy_name = 'dbatoolsci_agentproxy'"
        $destServer.Query($sql)
        $sql = "DROP CREDENTIAL dbatoolsci_credential"
        $destServer.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying agent proxy between instances" {
        BeforeAll {
            $splatCopyProxy = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                ProxyAccount = "dbatoolsci_agentproxy"
            }
            $copyResults = Copy-DbaAgentProxy @splatCopyProxy
        }

        It "Should return one successful result" {
            $global:dbatoolsciOutput = $copyResults
            $copyResults.Status.Count | Should -Be 1
            $copyResults.Status | Should -Be "Successful"
        }

        It "Should create the proxy on the destination" {
            $proxyResults = Get-DbaAgentProxy -SqlInstance $TestConfig.InstanceCopy2 -Proxy "dbatoolsci_agentproxy"
            $proxyResults.Name | Should -Be "dbatoolsci_agentproxy"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputItem = $global:dbatoolsciOutput | Where-Object Status
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $outputItem | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $outputItem.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
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
            $defaultColumns = $outputItem.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}