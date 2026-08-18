#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSuspectPage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Sanctioned per-record reset" {
            It "does not repeat a successful record after the next connection fails" {
                $originalConnect = Get-Item -Path Function:script:Connect-DbaInstance -ErrorAction SilentlyContinue
                $script:issue734ConnectCalls = 0
                function script:Connect-DbaInstance {
                    param($SqlInstance)

                    $script:issue734ConnectCalls++
                    if ("$SqlInstance" -eq "bad") {
                        throw "deterministic second-record connection failure"
                    }

                    $server = [pscustomobject]@{
                        ComputerName      = "fake"
                        ServiceName       = "fake"
                        DomainInstanceName = "good"
                    }
                    $server | Add-Member -MemberType ScriptMethod -Name Query -Value {
                        param($Sql)
                        @([pscustomobject]@{
                                DBName           = "seed"
                                file_id           = 1
                                page_id           = 1
                                EventType         = "Bad Checksum"
                                error_count       = 1
                                last_update_date  = [datetime]"2026-01-01"
                            })
                    }
                    $server
                }

                try {
                    $warnings = @()
                    $result = @("good", "bad") | Get-DbaSuspectPage -WarningVariable +warnings -WarningAction Continue

                    $script:issue734ConnectCalls | Should -Be 2
                    $warnings.Count | Should -Be 1
                    @($result).Count | Should -Be 1
                    $result.Database | Should -Be "seed"
                } finally {
                    if ($originalConnect) {
                        Set-Item -Path Function:script:Connect-DbaInstance -Value $originalConnect.ScriptBlock
                    } else {
                        Remove-Item -Path Function:script:Connect-DbaInstance -ErrorAction SilentlyContinue
                    }
                    Remove-Variable -Scope Script -Name issue734ConnectCalls -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if suspect pages are present" {
        BeforeAll {
            $dbname = "dbatoolsci_GetSuspectPage"
            $Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $Server -Database $dbname

            $null = $db.Query("
            CREATE TABLE dbo.[Example] (id int);
            INSERT dbo.[Example]
            SELECT top 1000 1
            FROM sys.objects")

            # make darn sure suspect pages show up, run twice
            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch { } # should fail

            try {
                $null = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbname
                $null = $db.Query("select top 100 from example")
                $null = $server.Query("ALTER DATABASE $dbname SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT")
                $null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
            } catch { } # should fail

            $results = Get-DbaSuspectPage -SqlInstance $server
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $Server -Database $dbname
        }

        It "function should find at least one record in suspect_pages table" {
            $results.Database -contains $dbname | Should -Be $true
        }
    }
}
