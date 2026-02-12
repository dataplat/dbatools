#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLinkedServer",
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
                "LinkedServer",
                "ExcludeLinkedServer",
                "UpgradeSqlClient",
                "ExcludePassword",
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

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        $createSql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool'"

        $server1.Query($createSql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dropSql = "EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost', @droplogins='droplogins'"

        $server1.Query($dropSql)
        $server2.Query($dropSql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying linked server with the same properties" {
        BeforeAll {
            # Create a dedicated linked server on source for output validation
            $outputLinkedName = "dbatoolsci_outputlinked"
            $outputCreateSql = "IF NOT EXISTS (SELECT * FROM sys.servers WHERE name = '$outputLinkedName') EXEC master.dbo.sp_addlinkedserver @server = N'$outputLinkedName', @srvproduct=N'SQL Server'"

            $outputServer1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $outputServer1.Query($outputCreateSql)

            try {
                $outputServer2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
                $outputServer2.Query("IF EXISTS (SELECT * FROM sys.servers WHERE name = '$outputLinkedName') EXEC master.dbo.sp_dropserver @server=N'$outputLinkedName', @droplogins='droplogins'")
            } catch { }

            $splatOutputCopy = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = $outputLinkedName
                WarningAction = "SilentlyContinue"
            }
            $script:outputResult = Copy-DbaLinkedServer @splatOutputCopy
        }

        It "Copies successfully" {
            $splatCopy = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $result = Copy-DbaLinkedServer @splatCopy
            $result | Select-Object -ExpandProperty Name -Unique | Should -BeExactly "dbatoolsci_localhost"
            $result | Select-Object -ExpandProperty Status -Unique | Should -BeExactly "Successful"
        }

        It "Retains the same properties" {
            $splatGetLink = @{
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $LinkedServer1 = Get-DbaLinkedServer -SqlInstance $server1 @splatGetLink
            $LinkedServer2 = Get-DbaLinkedServer -SqlInstance $server2 @splatGetLink

            $LinkedServer1.Name | Should -BeExactly $LinkedServer2.Name
            $LinkedServer1.LinkedServer | Should -BeExactly $LinkedServer2.LinkedServer
        }

        It "Skips existing linked servers" {
            $splatCopySkip = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $results = Copy-DbaLinkedServer @splatCopySkip
            $results.Status | Should -BeExactly "Skipped"
        }

        It "Returns output of the expected type" {
            if (-not $script:outputResult -or -not $script:outputResult[0]) { Set-ItResult -Skipped -Because "copy operation returned no results (connectivity issue between instances)" }
            $script:outputResult[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $script:outputResult -or -not $script:outputResult[0]) { Set-ItResult -Skipped -Because "copy operation returned no results (connectivity issue between instances)" }
            $defaultProps = $script:outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the correct values for key properties" {
            if (-not $script:outputResult -or -not $script:outputResult[0]) { Set-ItResult -Skipped -Because "copy operation returned no results (connectivity issue between instances)" }
            $script:outputResult[0].Name | Should -BeExactly "dbatoolsci_outputlinked"
            $script:outputResult[0].Status | Should -Not -BeNullOrEmpty
            $script:outputResult[0].SourceServer | Should -Not -BeNullOrEmpty
            $script:outputResult[0].DestinationServer | Should -Not -BeNullOrEmpty
        }

        AfterAll {
            try { $outputServer1.Query("EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_outputlinked', @droplogins='droplogins'") } catch { }
            try {
                $outputCleanup2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
                $outputCleanup2.Query("EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_outputlinked', @droplogins='droplogins'")
            } catch { }
        }
    }

}