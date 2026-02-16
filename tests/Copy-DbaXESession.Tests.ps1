#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "XeSession",
                "ExcludeXeSession",
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

        $xeSessionName = "dbatoolsci_xesession_$(Get-Random)"

        # Clean up any leftover XE session on destination
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
        $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
        $destStore = New-Object Microsoft.SqlServer.Management.XEvent.XEStore $destSqlStoreConnection
        if ($null -ne $destStore.Sessions[$xeSessionName]) {
            $destStore.Sessions[$xeSessionName].Drop()
        }

        # Create a custom XE session on the source instance
        $splatCreateXe = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Query       = "CREATE EVENT SESSION [$xeSessionName] ON SERVER ADD EVENT sqlserver.sql_statement_completed ADD TARGET package0.ring_buffer"
        }
        Invoke-DbaQuery @splatCreateXe

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the XE session from both instances
        foreach ($cleanupInstance in @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)) {
            $splatCleanupXe = @{
                SqlInstance   = $cleanupInstance
                Query         = "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = '$xeSessionName') DROP EVENT SESSION [$xeSessionName] ON SERVER"
                ErrorAction   = "SilentlyContinue"
                WarningAction = "SilentlyContinue"
            }
            Invoke-DbaQuery @splatCleanupXe
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying XE session between instances" {
        BeforeAll {
            $splatCopyXe = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                XeSession   = $xeSessionName
                Force       = $true
            }
            $results = @(Copy-DbaXESession @splatCopyXe -OutVariable "global:dbatoolsciOutput")
        }

        It "Should copy the XE session successfully" {
            $results | Should -Not -BeNullOrEmpty
            $results.Status | Should -BeExactly "Successful"
        }

        It "Should have the correct session name" {
            $results.Name | Should -BeExactly $xeSessionName
        }

        It "Should have the correct type" {
            $results.Type | Should -BeExactly "Extended Event"
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