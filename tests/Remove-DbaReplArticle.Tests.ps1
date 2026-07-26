#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplArticle",
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
                "Publication",
                "Schema",
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: removing an article needs a configured replication publisher/publication,
    # which the GitHub Actions replication harness provides (gh-actions-repl-*) - that live leg is
    # DEFERRED-TO-REPL-HARNESS. What IS characterizable with no replication configured is the
    # input guard the source runs before touching any instance: neither -SqlInstance nor
    # -InputObject supplied is rejected. The guard is connection-independent (probe-verified). This
    # command also emits a "Could not load replication libraries" warning when the Replication
    # assemblies are absent (as in the standalone drop) and not when they are present, so the total
    # warning count is environment dependent - the assertion checks that the guard message is among
    # the warnings (Should -Contain) rather than pinning an exact count. WhatIf is belt-and-braces
    # on this destructive (drop article) command; the guard returns before any gated action.
    Context "Guarding the input parameters" {
        It "Warns with the input guard and returns nothing when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Remove-DbaReplArticle @splatNoInput)
            $result.Count | Should -Be 0

            # strip the bracketed [timestamp]/[function] prefix from each warning; the input guard
            # message must be present regardless of the environment-dependent replication-library warning
            $payloads = $warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
            $payloads | Should -Contain "You must specify either SqlInstance or InputObject"
        }

        It "Refuses an unscoped instance lookup without reaching or removing an article" {
            InModuleScope dbatools {
                $article = [pscustomobject]@{
                    Name              = "unscoped"
                    ComputerName      = "fixture-computer"
                    InstanceName      = "fixture-instance"
                    SqlInstance       = "fixture-instance"
                    DatabaseName      = "fixture-database"
                    PublicationName   = "fixture-publication"
                    SourceObjectOwner = "dbo"
                    SourceObjectName  = "unscoped"
                    IsExistingObject  = $true
                    State             = [pscustomobject]@{ RemoveCalls = 0 }
                }
                $article | Add-Member -MemberType ScriptMethod -Name Remove -Value {
                    $this.State.RemoveCalls++
                }

                Mock Get-DbaReplArticle { $article }

                $warnings = @()
                $result = @(
                    Remove-DbaReplArticle -SqlInstance "fixture-instance" -Confirm:$false `
                        -WarningVariable warnings -WarningAction SilentlyContinue
                )
                $payloads = @($warnings | ForEach-Object {
                    $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", ""
                })

                $result.Count | Should -Be 0
                $payloads | Should -Contain "You must specify at least one of Database, Publication, or Name when using SqlInstance"
                Should -Invoke Get-DbaReplArticle -Exactly -Times 0
                $article.State.RemoveCalls | Should -Be 0
            }
        }

        It "Throws for the same refusal when EnableException is requested" {
            InModuleScope dbatools {
                Mock Get-DbaReplArticle { throw "lookup must not execute" }

                {
                    Remove-DbaReplArticle -SqlInstance "fixture-instance" -EnableException -Confirm:$false
                } | Should -Throw "*You must specify at least one of Database, Publication, or Name when using SqlInstance*"
                Should -Invoke Get-DbaReplArticle -Exactly -Times 0
            }
        }
    }

    Context "Preserving scoped and piped removal behavior" {
        It "Reaches ShouldProcess for a scoped WhatIf lookup without removing the article" {
            InModuleScope dbatools {
                $childPath = Join-Path $TestDrive "remove-repl-article-whatif.ps1"
                $moduleManifest = Join-Path (Split-Path $PSScriptRoot -Parent) "dbatools.psd1"
                @'
param([Parameter(Mandatory)][string]$ModulePath)
$ErrorActionPreference = "Stop"
Import-Module $ModulePath -Force
$module = Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1
$article = [pscustomobject]@{
    Name              = "whatif"
    ComputerName      = "fixture-computer"
    InstanceName      = "fixture-instance"
    SqlInstance       = "fixture-instance"
    DatabaseName      = "fixture-database"
    PublicationName   = "fixture-publication"
    SourceObjectOwner = "dbo"
    SourceObjectName  = "whatif"
    IsExistingObject  = $true
    State             = [pscustomobject]@{ RemoveCalls = 0 }
}
$article | Add-Member -MemberType ScriptMethod -Name Remove -Value {
    $this.State.RemoveCalls++
}
$module.SessionState.PSVariable.Set("RemoveReplArticleWhatIf", $article)
$module.SessionState.PSVariable.Set("RemoveReplArticleLookupCalls", 0)
& $module {
    function script:Get-DbaReplArticle {
        $script:RemoveReplArticleLookupCalls++
        $script:RemoveReplArticleWhatIf
    }
}
$null = Remove-DbaReplArticle -SqlInstance "fixture-instance" -Name "whatif" -WhatIf -Confirm:$false
Write-Output "LOOKUP_CALLS=$(& $module { $script:RemoveReplArticleLookupCalls })"
Write-Output "REMOVE_CALLS=$($article.State.RemoveCalls)"
'@ | Set-Content -LiteralPath $childPath

                $executable = if ($PSVersionTable.PSEdition -eq "Desktop") {
                    Join-Path $PSHOME "powershell.exe"
                } else {
                    Join-Path $PSHOME "pwsh.exe"
                }
                $whatIfOutput = @(& $executable -NoProfile -File $childPath -ModulePath $moduleManifest 2>&1) |
                    ForEach-Object { "$PSItem" }

                $whatIfOutput | Should -Contain "LOOKUP_CALLS=1"
                $whatIfOutput | Should -Contain "REMOVE_CALLS=0"
                ($whatIfOutput -join "`n") | Should -Match 'What if: Performing the operation "Removing the article dbo\.whatif from the fixture-publication publication on fixture-instance" on target "whatif"\.'
            }
        }

        It "Removes and emits each article in a two-record pipeline" {
            InModuleScope dbatools {
                $first = [pscustomobject]@{
                    Name              = "first"
                    ComputerName      = "fixture-computer"
                    InstanceName      = "fixture-instance"
                    SqlInstance       = "fixture-instance"
                    DatabaseName      = "fixture-database"
                    PublicationName   = "fixture-publication"
                    SourceObjectOwner = "dbo"
                    SourceObjectName  = "first"
                    IsExistingObject  = $true
                    State             = [pscustomobject]@{ RemoveCalls = 0 }
                }
                $second = $first.PSObject.Copy()
                $second.Name = "second"
                $second.SourceObjectName = "second"
                $second.State = [pscustomobject]@{ RemoveCalls = 0 }
                $first | Add-Member -MemberType ScriptMethod -Name Remove -Value {
                    $this.State.RemoveCalls++
                }
                $second | Add-Member -MemberType ScriptMethod -Name Remove -Value {
                    $this.State.RemoveCalls++
                }

                Mock Get-DbaReplPublication {
                    [pscustomobject]@{ Subscriptions = @() }
                }

                $result = @($first, $second | Remove-DbaReplArticle -Confirm:$false)

                $first.State.RemoveCalls | Should -Be 1
                $second.State.RemoveCalls | Should -Be 1
                $result.Count | Should -Be 2
                Should -Invoke Get-DbaReplPublication -Exactly -Times 2
            }
        }
    }
}
