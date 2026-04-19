#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaPolicyManagement",
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
                "Policy",
                "ExcludePolicy",
                "Condition",
                "ExcludeCondition",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Object set selection" {
        It "copies only object sets required by selected policies" {
            $executedQueries = InModuleScope dbatools {
                function New-MockScriptedPbmObject {
                    param(
                        [string]$Name,
                        [string]$ScriptText,
                        [string]$ObjectSet,
                        [string]$PolicyCategory
                    )

                    $mockPbmObject = [PSCustomObject]@{
                        Name           = $Name
                        IsSystemObject = $false
                        ObjectSet      = $ObjectSet
                        PolicyCategory = $PolicyCategory
                        ScriptText     = $ScriptText
                    }

                    $mockPbmObject | Add-Member -Force -MemberType ScriptMethod -Name ScriptCreate -Value {
                        $scriptResult = [PSCustomObject]@{
                            ScriptText = $this.ScriptText
                        }
                        $scriptResult | Add-Member -Force -MemberType ScriptMethod -Name GetScript -Value { $this.ScriptText }
                        $scriptResult
                    }

                    $mockPbmObject
                }

                function New-MockPbmServer {
                    param(
                        [string]$Name
                    )

                    $mockServer = [PSCustomObject]@{
                        Name              = $Name
                        ConnectionContext = [PSCustomObject]@{
                            SqlConnectionObject = "$Name-Connection"
                        }
                    }

                    $mockServer | Add-Member -Force -MemberType ScriptMethod -Name Query -Value {
                        param($Sql)
                        $script:executedQueries += $Sql.Trim()
                        $null
                    }

                    $mockServer
                }

                function Add-PbmLibrary { }
                function Test-FunctionInterrupt { $false }
                function Write-Message { }
                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        [Parameter(ValueFromRemainingArguments)]
                        $RemainingArguments
                    )

                    process {
                        $InputObject
                    }
                }
                function Connect-DbaInstance {
                    param($SqlInstance)

                    if ($SqlInstance -eq "source1") {
                        $script:mockSourceServer
                    } else {
                        $script:mockDestinationServer
                    }
                }
                function New-Object {
                    param(
                        [string]$TypeName,
                        [Parameter(ValueFromRemainingArguments)]
                        $ArgumentList
                    )

                    if ($TypeName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection") {
                        return [PSCustomObject]@{ }
                    }

                    if ($TypeName -eq "Microsoft.SqlServer.Management.DMF.PolicyStore") {
                        $script:policyStoreCallCount++
                        if ($script:policyStoreCallCount -eq 1) {
                            return $script:mockSourceStore
                        }
                        return $script:mockDestinationStore
                    }

                    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
                }

                $script:executedQueries = @()
                $script:policyStoreCallCount = 0
                $script:mockSourceServer = New-MockPbmServer -Name "source1"
                $script:mockDestinationServer = New-MockPbmServer -Name "destination1"

                $mockDestinationPolicies = @{ }
                $mockDestinationPolicies | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationConditions = @{ }
                $mockDestinationConditions | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationObjectSets = @{ }
                $mockDestinationObjectSets | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationPolicyCategories = @{ }
                $mockDestinationPolicyCategories | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $script:mockSourceStore = [PSCustomObject]@{
                    Policies         = @(
                        (New-MockScriptedPbmObject -Name "PolicyA" -ObjectSet "ObjectSetA" -PolicyCategory "PolicyCategoryA" -ScriptText "CREATE POLICY [PolicyA]"),
                        (New-MockScriptedPbmObject -Name "PolicyB" -ObjectSet "ObjectSetB" -PolicyCategory "PolicyCategoryB" -ScriptText "CREATE POLICY [PolicyB]")
                    )
                    Conditions       = @()
                    ObjectSets       = @(
                        (New-MockScriptedPbmObject -Name "ObjectSetA" -ScriptText "CREATE OBJECT SET [ObjectSetA]"),
                        (New-MockScriptedPbmObject -Name "ObjectSetB" -ScriptText "CREATE OBJECT SET [ObjectSetB]")
                    )
                    PolicyCategories = @()
                }

                $script:mockDestinationStore = [PSCustomObject]@{
                    Policies         = $mockDestinationPolicies
                    Conditions       = $mockDestinationConditions
                    ObjectSets       = $mockDestinationObjectSets
                    PolicyCategories = $mockDestinationPolicyCategories
                }

                $null = Copy-DbaPolicyManagement -Source "source1" -Destination "destination1" -Policy "PolicyA"

                $script:executedQueries
            }

            $executedQueries | Should -Contain "CREATE OBJECT SET [ObjectSetA]"
            $executedQueries | Should -Contain "CREATE POLICY [PolicyA]"
            $executedQueries | Should -Not -Contain "CREATE OBJECT SET [ObjectSetB]"
        }
    }
}