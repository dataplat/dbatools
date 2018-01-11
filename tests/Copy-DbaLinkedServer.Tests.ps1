$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        if ($env:appveyor) {
            try {
                $connstring = "Server=ADMIN:$script:instance1;Trusted_Connection=True"
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server $script:instance1
                $server.ConnectionContext.ConnectionString = $connstring
                $server.ConnectionContext.Connect()
                $server.ConnectionContext.Disconnect()
            }
            catch {
                $bail = $true
                Write-Host "DAC not working this round, likely due to Appveyor resources"
            }
        }

        $dropsql = "EXEC master.dbo.sp_dropserver @server=N'dbatools-localhost', @droplogins='droplogins';
            EXEC master.dbo.sp_dropserver @server=N'dbatools-localhost2', @droplogins='droplogins'"

        $createsql = "EXEC master.dbo.sp_addlinkedserver @server = N'dbatools-localhost', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatools-localhost',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';
        EXEC master.dbo.sp_addlinkedserver @server = N'dbatools-localhost2', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'dbatools-localhost2',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool';"

        try {
            $server1 = Connect-DbaInstance -SqlInstance $script:instance1
            $server2 = Connect-DbaInstance -SqlInstance $script:instance2
            $server1.Query($createsql)
        }
        catch {
            $bail = $true
            Write-Host "Couldn't setup Linked Servers, bailing"
        }
    }

    AfterAll {
        try {
            $server1.Query($dropsql)
            $dropsql = "EXEC master.dbo.sp_dropserver @server=N'dbatools-localhost', @droplogins='droplogins'"
            $server2.Query($dropsql)
        }
        catch {}
    }

    if ($bail) { return }

    Context "Copy Credential with the same properties" {
        It "copies successfully" {
            $result = Copy-DbaLinkedServer -Source $server1 -Destination $server2 -LinkedServer dbatools-localhost -WarningAction SilentlyContinue
            $result.Name | Should Be "dbatools-localhost"
            $result.Status | Should Be "Successful"
        }

        It "retains the same properties" {
            $LinkedServer1 = Get-DbaLinkedServer -SqlInstance $server1 -LinkedServer dbatools-localhost -WarningAction SilentlyContinue
            $LinkedServer2 = Get-DbaLinkedServer -SqlInstance $server2 -LinkedServer dbatools-localhost -WarningAction SilentlyContinue

            # Compare its value
            $LinkedServer1.Name | Should Be $LinkedServer2.Name
            $LinkedServer1.LinkedServer | Should Be $LinkedServer2.LinkedServer
        }

        $results = Copy-DbaLinkedServer -Source $server1 -Destination $server2 -LinkedServer dbatools-localhost -WarningAction SilentlyContinue
        $results.Status | Should Be "Skipped"
    }
}