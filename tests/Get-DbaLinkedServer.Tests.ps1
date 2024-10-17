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
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have LinkedServer as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter LinkedServer -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeLinkedServer as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeLinkedServer -Type Object[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
