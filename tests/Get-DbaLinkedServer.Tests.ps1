$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'ExcludeLinkedServer', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("EXEC master.dbo.sp_addlinkedserver
            @server = N'$script:instance3',
            @srvproduct=N'SQL Server' ;")
    }
    AfterAll {
        $null = $server.Query("EXEC master.dbo.sp_dropserver '$script:instance3', 'droplogins';  ")
    }

    Context "Gets Linked Servers" {
        $results = Get-DbaLinkedServer -SqlInstance $script:instance2 | Where-Object {$_.name -eq "$script:instance3"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Remote Server of $script:instance3" {
            $results.RemoteServer | Should Be "$script:instance3"
        }
        It "Should have a product name of SQL Server" {
            $results.productname | Should Be 'SQL Server'
        }
        It "Should have Impersonate for authentication" {
            $results.Impersonate | Should Be $true
        }
    }
    Context "Gets Linked Servers using -LinkedServer" {
        $results = Get-DbaLinkedServer -SqlInstance $script:instance2 -LinkedServer "$script:instance3"
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Remote Server of $script:instance3" {
            $results.RemoteServer | Should Be "$script:instance3"
        }
        It "Should have a product name of SQL Server" {
            $results.productname | Should Be 'SQL Server'
        }
        It "Should have Impersonate for authentication" {
            $results.Impersonate | Should Be $true
        }
    }
    Context "Gets Linked Servers using -ExcludeLinkedServer" {
        $results = Get-DbaLinkedServer -SqlInstance $script:instance2 -ExcludeLinkedServer "$script:instance3"
        It "Gets results" {
            $results | Should Be $null
        }
    }
}