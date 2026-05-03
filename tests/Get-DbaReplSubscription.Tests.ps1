#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplSubscription",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "PublicationName",
                "SubscriberName",
                "SubscriptionDatabase",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Distribution database fallback" {
            BeforeAll {
                Mock Add-ReplicationLibrary { }
                Mock Connect-ReplicationDB {
                    [PSCustomObject]@{
                        Name              = "SalesDb"
                        TransPublications = @(
                            [PSCustomObject]@{
                                Name               = "SalesPub"
                                Type               = "Transactional"
                                DatabaseName       = "SalesDb"
                                PubId              = 42
                                TransSubscriptions = @()
                            }
                        )
                        MergePublications = @()
                    }
                }
                Mock Test-FunctionInterrupt { $false }
                Mock Write-Message { }
                Mock Select-DefaultView { $InputObject }
                Mock Stop-Function {
                    throw "$Message :: $($ErrorRecord.Exception.Message)"
                }
                Mock Connect-DbaInstance {
                    $server = [DbaInstanceParameter]"Publisher01"
                    $server | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "Publisher01"
                    $server | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
                    $server | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "Publisher01"
                    $server | Add-Member -Force -MemberType NoteProperty -Name Databases -Value @(
                        [PSCustomObject]@{
                            Name               = "SalesDb"
                            ReplicationOptions = "Published"
                            IsAccessible       = $true
                            IsSystemObject     = $false
                        }
                    )
                    $server | Add-Member -Force -MemberType NoteProperty -Name ConnectionContext -Value ([PSCustomObject]@{
                            SqlConnectionObject = "FakeConnectionContext"
                        })
                    $server
                }
                Mock New-Object {
                    [PSCustomObject]@{
                        ConnectionContext    = $null
                        IsPublisher          = $true
                        DistributorInstalled = $true
                        DistributorAvailable = $true
                        DistributionServer   = "Publisher01"
                        DistributionDatabase = "distribution"
                    }
                } -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Replication.ReplicationServer"
                }
                Mock Invoke-DbaQuery {
                    @(
                        [PSCustomObject]@{
                            SubscriberName     = "Subscriber01"
                            SubscriptionDBName = "SalesSubscriberDb"
                            DatabaseName       = "SalesDb"
                            PublicationName    = "SalesPub"
                            PublicationId      = 42
                        },
                        [PSCustomObject]@{
                            SubscriberName     = "Subscriber02"
                            SubscriptionDBName = "SalesSubscriberDb"
                            DatabaseName       = "SalesDb"
                            PublicationName    = "SalesPub"
                            PublicationId      = 99
                        }
                    )
                }
            }

            It "Filters distribution-only pull subscriptions to the current publication id" {
                $results = @(Get-DbaReplSubscription -SqlInstance "Publisher01")

                $results.Count | Should -Be 1
                $results.PublicationName | Should -Be "SalesPub"
                $results.DatabaseName | Should -Be "SalesDb"
                $results.SubscriberName | Should -Be "Subscriber01"
            }
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>