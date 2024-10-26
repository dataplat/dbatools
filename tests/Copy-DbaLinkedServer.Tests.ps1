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
        $splatSource = @{
            SqlInstance = $TestConfig.instance2
        }
        $splatDestination = @{
            SqlInstance = $TestConfig.instance3
        }

        $createsql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';
        EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost2', @srvproduct=N'', @provider=N'SQLNCLI10';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost2',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';"

        $sourceServer = Connect-DbaInstance @splatSource
        $destServer = Connect-DbaInstance @splatDestination
        $sourceServer.Query($createsql)
    }

    AfterAll {
        $dropsql = "EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost', @droplogins='droplogins';
        EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost2', @droplogins='droplogins'"

        try {
            $sourceServer.Query($dropsql)
            $destServer.Query($dropsql)
        } catch {
            # Ignore cleanup errors
        }
    }

    Context "When copying linked server with the same properties" {
        BeforeAll {
            $splatCopy = @{
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                LinkedServer = "dbatoolsci_localhost"
                WarningAction = "SilentlyContinue"
            }
        }

        It "Copies successfully" {
            $result = Copy-DbaLinkedServer @splatCopy
            $result.Name | Select-Object -Unique | Should -Be "dbatoolsci_localhost"
            $result.Status | Select-Object -Unique | Should -Be "Successful"
        }

        It "Retains the same properties" {
            $sourceLinkedServer = Get-DbaLinkedServer -SqlInstance $sourceServer -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue
            $destLinkedServer = Get-DbaLinkedServer -SqlInstance $destServer -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue

            $destLinkedServer.Name | Should -Be $sourceLinkedServer.Name
            $destLinkedServer.LinkedServer | Should -Be $sourceLinkedServer.LinkedServer
        }

        It "Skips existing linked servers" {
            $results = Copy-DbaLinkedServer @splatCopy
            $results.Status | Should -Be "Skipped"
        }

        It "Upgrades SQLNCLI provider based on what is registered" -Skip:($sourceServer.VersionMajor -gt 14 -or $destServer.VersionMajor -gt 14) {
            $splatUpgrade = @{
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                LinkedServer = "dbatoolsci_localhost2"
                UpgradeSqlClient = $true
            }
            $null = Copy-DbaLinkedServer @splatUpgrade

            $sourceServer = Connect-DbaInstance @splatSource
            $destServer = Connect-DbaInstance @splatDestination

            $sourceScript = $sourceServer.LinkedServers['dbatoolsci_localhost2'].Script()
            $destScript = $destServer.LinkedServers['dbatoolsci_localhost2'].Script()

            $sourceScript | Should -Match 'SQLNCLI\d+'
            $destScript | Should -Match 'SQLNCLI\d+'
            # Verify destination has same or higher version
            $sourceVersion = [regex]::Match($sourceScript, 'SQLNCLI(\d+)').Groups[1].Value
            $destVersion = [regex]::Match($destScript, 'SQLNCLI(\d+)').Groups[1].Value
            [int]$destVersion | Should -BeGreaterOrEqual ([int]$sourceVersion)
        }
    }
}
