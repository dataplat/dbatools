param($ModuleName = 'dbatools')

Describe "Get-DbaLinkedServer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLinkedServer
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "LinkedServer",
                "ExcludeLinkedServer",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $null = $server.Query("EXEC master.dbo.sp_addlinkedserver
                @server = N'$global:instance3',
                @srvproduct=N'SQL Server' ;")
        }
        AfterAll {
            $null = $server.Query("EXEC master.dbo.sp_dropserver '$global:instance3', 'droplogins';  ")
        }

        Context "Gets Linked Servers" {
            BeforeAll {
                $results = Get-DbaLinkedServer -SqlInstance $global:instance2 | Where-Object {$_.name -eq "$global:instance3"}
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have Remote Server of $global:instance3" {
                $results.RemoteServer | Should -Be "$global:instance3"
            }
            It "Should have a product name of SQL Server" {
                $results.productname | Should -Be 'SQL Server'
            }
            It "Should have Impersonate for authentication" {
                $results.Impersonate | Should -BeTrue
            }
        }

        Context "Gets Linked Servers using -LinkedServer" {
            BeforeAll {
                $results = Get-DbaLinkedServer -SqlInstance $global:instance2 -LinkedServer "$global:instance3"
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have Remote Server of $global:instance3" {
                $results.RemoteServer | Should -Be "$global:instance3"
            }
            It "Should have a product name of SQL Server" {
                $results.productname | Should -Be 'SQL Server'
            }
            It "Should have Impersonate for authentication" {
                $results.Impersonate | Should -BeTrue
            }
        }

        Context "Gets Linked Servers using -ExcludeLinkedServer" {
            BeforeAll {
                $results = Get-DbaLinkedServer -SqlInstance $global:instance2 -ExcludeLinkedServer "$global:instance3"
            }
            It "Gets results" {
                $results | Should -BeNullOrEmpty
            }
        }
    }
}
