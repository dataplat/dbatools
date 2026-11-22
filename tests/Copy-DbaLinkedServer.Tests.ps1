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
                "Credential",
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
    }

    Context "When copying a SQL Server linked server whose network name differs from its name" {
        BeforeAll {
            # The copy runs sp_setnetname on the destination only for such a linked server
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $netNameSql = @"
EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_netname', @srvproduct = N'SQL Server';
EXEC master.dbo.sp_setnetname @server = N'dbatoolsci_netname', @netname = N'localhost';
"@
            $null = $server1.Query($netNameSql)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatCopyNetName = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_netname"
                WarningAction = "SilentlyContinue"
            }
            $netNameResults = Copy-DbaLinkedServer @splatCopyNetName
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dropNetNameSql = @"
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = N'dbatoolsci_netname')
    EXEC master.dbo.sp_dropserver @server = N'dbatoolsci_netname', @droplogins = 'droplogins';
"@
            $null = $server1.Query($dropNetNameSql)
            $null = $server2.Query($dropNetNameSql)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns one successful result" {
            # Counts the output itself, $netNameResults.Status.Count would skip a $null written by the command
            @($netNameResults).Count | Should -Be 1
            $netNameResults.Status | Should -BeExactly "Successful"
        }

        It "Keeps the network name on the destination" {
            $server2.LinkedServers.Refresh()
            $server2.LinkedServers["dbatoolsci_netname"].DataSource | Should -BeExactly "localhost"
        }
    }

    Context "When the pipeline ends at the first linked server" {
        It "Closes the dedicated admin connection" {
            # The command opens a dedicated admin connection to the source for the passwords. It was closed in the end
            # block only, which Select-Object -First 1 skips, and SQL Server allows only one per instance.
            $splatFirstLinkedServer = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                LinkedServer  = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
            $firstLinkedServer = Copy-DbaLinkedServer @splatFirstLinkedServer | Select-Object -First 1
            $firstLinkedServer.Name | Should -BeExactly "dbatoolsci_localhost"

            $dacSessionQuery = "SELECT COUNT(*) AS DacSessions FROM sys.dm_exec_sessions AS s INNER JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE e.is_admin_endpoint = 1"
            # The session can take a moment to end on the server after the client closed the connection.
            $dacWatch = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                $dacSessions = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query $dacSessionQuery).DacSessions
                if ($dacSessions -gt 0) {
                    Start-Sleep -Milliseconds 200
                }
            } while ($dacSessions -gt 0 -and $dacWatch.Elapsed.TotalSeconds -lt 5)
            $dacSessions | Should -Be 0
        }
    }
}