$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $createsql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';
        EXEC master.dbo.sp_addlinkedserver @server = N'dbatoolsci_localhost2', @srvproduct=N'', @provider=N'SQLNCLI10';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatoolsci_localhost2',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';"
        
        $server1 = Connect-DbaInstance -SqlInstance $script:instance2
        $server2 = Connect-DbaInstance -SqlInstance $script:instance3
        $server1.Query($createsql)
    }
    AfterAll {
        $dropsql = "EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost', @droplogins='droplogins';
        EXEC master.dbo.sp_dropserver @server=N'dbatoolsci_localhost2', @droplogins='droplogins'"

        try {
            $server1.Query($dropsql)
            $server2.Query($dropsql)
        }
        catch {}
    }

    Context "Copy linked server with the same properties" {
        It "copies successfully" {
            $result = Copy-DbaLinkedServer -Source $server1 -Destination $server2 -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue
            $result | Select-Object -ExpandProperty Name -Unique | Should Be "dbatoolsci_localhost"
            $result | Select-Object -ExpandProperty Status -Unique | Should Be "Successful"
        }

        It "retains the same properties" {
            $LinkedServer1 = Get-DbaLinkedServer -SqlInstance $server1 -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue
            $LinkedServer2 = Get-DbaLinkedServer -SqlInstance $server2 -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue

            # Compare its value
            $LinkedServer1.Name | Should Be $LinkedServer2.Name
            $LinkedServer1.LinkedServer | Should Be $LinkedServer2.LinkedServer
        }

        It "skips existing linked servers" {
            $results = Copy-DbaLinkedServer -Source $server1 -Destination $server2 -LinkedServer dbatoolsci_localhost -WarningAction SilentlyContinue
            $results.Status | Should Be "Skipped"
        }

        It "upgrades SQLNCLI provider based on what is registered" {
            $result = Copy-DbaLinkedServer -Source $server1 -Destination $server2 -LinkedServer dbatoolsci_localhost2 -UpgradeSqlClient
            $server1.LinkedServers.Script() -match 'SQLNCLI10' | Should -Not -BeNullOrEmpty
            $server2.LinkedServers.Script() -match 'SQLNCLI11' | Should -Not -BeNullOrEmpty
        }
    }
}