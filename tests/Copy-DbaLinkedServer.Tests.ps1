#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaLinkedServer" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaLinkedServer
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "LinkedServer",
                "ExcludeLinkedServer",
                "UpgradeSqlClient",
                "ExcludePassword",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaLinkedServer" -Tag "IntegrationTests" {
    BeforeAll {
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance3

        $createSql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';
        EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost2', @srvproduct=N'', @provider=N'SQLNCLI10';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost2',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';"

        $server1.Query($createSql)
    }

    AfterAll {
        $dropSql = "EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost', @droplogins='droplogins';
        EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost2', @droplogins='droplogins'"
        try {
            $server1.Query($dropSql)
            $server2.Query($dropSql)
        } catch {
            # Silently continue
        }
    }

    Context "When copying linked server with the same properties" {
        It "Copies successfully" {
            $copySplat = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                LinkedServer  = 'dbatoolsci_localhost'
                WarningAction = 'SilentlyContinue'
            }
            $result = Copy-DbaLinkedServer @copySplat
            $result | Select-Object -ExpandProperty Name -Unique | Should -BeExactly "dbatoolsci_localhost"
            $result | Select-Object -ExpandProperty Status -Unique | Should -BeExactly "Successful"
        }

        It "Retains the same properties" {
            $getLinkSplat = @{
                LinkedServer  = 'dbatoolsci_localhost'
                WarningAction = 'SilentlyContinue'
            }
            $LinkedServer1 = Get-DbaLinkedServer -SqlInstance $server1 @getLinkSplat
            $LinkedServer2 = Get-DbaLinkedServer -SqlInstance $server2 @getLinkSplat

            $LinkedServer1.Name | Should -BeExactly $LinkedServer2.Name
            $LinkedServer1.LinkedServer | Should -BeExactly $LinkedServer2.LinkedServer
        }

        It "Skips existing linked servers" {
            $copySplat = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                LinkedServer  = 'dbatoolsci_localhost'
                WarningAction = 'SilentlyContinue'
            }
            $results = Copy-DbaLinkedServer @copySplat
            $results.Status | Should -BeExactly "Skipped"
        }
    }
}