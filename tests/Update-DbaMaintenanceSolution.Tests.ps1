#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaMaintenanceSolution",
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
                "Solution",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Source refresh behavior" {
        InModuleScope dbatools {
            BeforeEach {
                $script:maintenanceCacheExists = $true
                $script:maintenanceServer = [DbaInstanceParameter]"sql1"
                $script:maintenanceServer | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value "sql1"
                $script:maintenanceServer | Add-Member -Force -MemberType NoteProperty -Name ServiceName -Value "MSSQLSERVER"
                $script:maintenanceServer | Add-Member -Force -MemberType NoteProperty -Name DomainInstanceName -Value "sql1"
                $script:maintenanceServer | Add-Member -Force -MemberType NoteProperty -Name Databases -Value @([PSCustomObject]@{ Name = "master" })

                Mock Get-DbatoolsConfigValue { "C:\dbatools-data" }
                Mock Join-DbaPath { "C:\dbatools-data\sql-server-maintenance-solution-main" }
                Mock Test-Path { $script:maintenanceCacheExists }
                Mock Save-DbaCommunitySoftware { }
                Mock Connect-DbaInstance { $script:maintenanceServer }
                Mock Get-DbaModule { @() }
                Mock Disconnect-DbaInstance { }
                Mock Test-FunctionInterrupt { $false }
                Mock Stop-Function { }
                Mock Write-Message { }
            }

            It "attempts a refresh with an existing cache and passes LocalFile <InputLocalFile>" -ForEach @(
                @{ InputLocalFile = $null; ExpectedLocalFile = "" }
                @{ InputLocalFile = "C:\packages\maintenance-solution.zip"; ExpectedLocalFile = "C:\packages\maintenance-solution.zip" }
            ) {
                $splatUpdate = @{
                    SqlInstance = "sql1"
                    Confirm     = $false
                }
                if ($null -ne $InputLocalFile) {
                    $splatUpdate.LocalFile = $InputLocalFile
                }

                $null = Update-DbaMaintenanceSolution @splatUpdate

                Should -Invoke Save-DbaCommunitySoftware -Times 1 -Exactly -ParameterFilter {
                    $Software -eq "MaintenanceSolution" -and $LocalFile -eq $ExpectedLocalFile -and $EnableException
                }
            }

            It "falls back only when an online refresh fails and cache availability is <CacheExists>" -ForEach @(
                @{ CacheExists = $true; ExpectedStops = 0; ExpectedWarnings = 1 }
                @{ CacheExists = $false; ExpectedStops = 1; ExpectedWarnings = 0 }
            ) {
                $script:maintenanceCacheExists = $CacheExists
                Mock Save-DbaCommunitySoftware { throw "offline" }

                $null = Update-DbaMaintenanceSolution -SqlInstance "sql1" -Confirm:$false

                Should -Invoke Stop-Function -Times $ExpectedStops -Exactly -ParameterFilter {
                    $Message -eq "Failed to update local cached copy"
                }
                Should -Invoke Write-Message -Times $ExpectedWarnings -Exactly -ParameterFilter {
                    $Level -eq "Warning" -and $Message -like "*Using existing cached copy*"
                }
            }

            It "does not fall back when a supplied LocalFile fails and warns that Force is redundant" {
                Mock Save-DbaCommunitySoftware { throw "bad package" }

                $null = Update-DbaMaintenanceSolution -SqlInstance "sql1" -LocalFile "C:\packages\bad.zip" -Force -Confirm:$false

                Should -Invoke Stop-Function -Times 1 -Exactly -ParameterFilter {
                    $Message -eq "Failed to update local cached copy"
                }
                Should -Invoke Write-Message -Times 1 -Exactly -ParameterFilter {
                    $Level -eq "Warning" -and $Message -like "*Force*refresh*every invocation*"
                }
            }

            It "explains that Force still suppresses confirmation prompts" {
                $null = Update-DbaMaintenanceSolution -SqlInstance "sql1" -Force -Confirm:$false

                Should -Invoke Write-Message -Times 1 -Exactly -ParameterFilter {
                    $Level -eq "Warning" -and $Message -like "*Force*still suppresses confirmation prompts*"
                }
            }
        }
    }
}
