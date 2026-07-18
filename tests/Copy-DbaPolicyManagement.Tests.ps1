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

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the actual copy migrates Policy-Based Management policies, conditions, and
    # object sets from a source to a destination instance, which needs a live Source+Destination
    # pair - that behavior leg is DEFERRED-TO-COPYPAIR (the standing Source+Destination gate pair
    # for the Copy-* family, per the coordinator ruling 2026-07-18; the mocked UnitTests above
    # already pin the policy/objectset copy dispatch). What IS characterizable deterministically is
    # the platform guard the source runs first: on a non-Windows host the command refuses to run.
    # Per the coordinator ruling this is pinned by flipping the module-scope $script:isWindows state
    # (InModuleScope), never by mocking Connect-DbaInstance (the documented mock-coupling latent-red
    # class); the flip is restored in a finally so it cannot leak into other tests.
    Context "Guarding on a non-Windows platform" {
        It "Warns and returns nothing when the host is not Windows" {
            InModuleScope dbatools {
                # [char]39 supplies the apostrophe the source message contains (the contraction of
                # "we are") without a literal apostrophe in the test source
                $q = [char]39
                $originalIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "warn"
                        WarningAction   = "SilentlyContinue"
                        WhatIf          = $true
                    }
                    $result = @(Copy-DbaPolicyManagement @splatNonWindows)
                    $result.Count | Should -Be 0
                    $warn.Count | Should -Be 1

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                    $payload | Should -Be "Copy-DbaPolicyManagement does not support Linux - we${q}re still waiting for the Core SMOs from Microsoft"
                } finally {
                    $script:isWindows = $originalIsWindows
                }
            }
        }
    }
}
