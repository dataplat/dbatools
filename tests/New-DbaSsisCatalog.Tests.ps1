#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSsisCatalog",
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
                "Credential",
                "SecurePassword",
                "SsisCatalog",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    if ($PSVersionTable.PSEdition -eq "Desktop") {
        Context "Processes each piped instance with fresh service state" {
            BeforeEach {
                $global:newDbaSsisCatalogServiceLookups = 0
                $global:newDbaSsisCatalogFallbackLookups = 0
                Mock Connect-DbaInstance -ModuleName dbatools -MockWith {
                    param($SqlInstance)
                    @($SqlInstance)[0]
                }
                Mock Get-DbaService -ModuleName dbatools -MockWith {
                    $global:newDbaSsisCatalogServiceLookups++
                    if ($global:newDbaSsisCatalogServiceLookups -eq 2) {
                        throw "simulated service lookup failure"
                    }
                    [PSCustomObject]@{
                        ServiceType = "SSIS"
                        State       = "Running"
                    }
                }
                Mock Invoke-Command2 -ModuleName dbatools -MockWith {
                    $global:newDbaSsisCatalogFallbackLookups++
                    [PSCustomObject]@{
                        Name   = "MsDtsServer150"
                        Status = "Running"
                    }
                }
                Mock Get-DbaSpConfigure -ModuleName dbatools -MockWith {
                    [PSCustomObject]@{ RunningValue = $true }
                }
                Mock New-Object -ModuleName dbatools -ParameterFilter {
                    $TypeName -eq "Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices"
                } -MockWith {
                    [PSCustomObject]@{ Catalogs = @([PSCustomObject]@{ Name = "SSISDB" }) }
                }
            }

            AfterEach {
                Remove-Variable newDbaSsisCatalogServiceLookups -Scope Global -ErrorAction SilentlyContinue
                Remove-Variable newDbaSsisCatalogFallbackLookups -Scope Global -ErrorAction SilentlyContinue
            }

            It "uses the fallback only for the record whose service lookup fails" {
                $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
                $instances = @(
                    [DbaInstanceParameter]"pipe-one.example.test"
                    [DbaInstanceParameter]"pipe-two.example.test"
                )

                $warnings = @()
                $errors = @()
                $result = @(
                    $instances | New-DbaSsisCatalog -SecurePassword $password `
                        -WarningVariable warnings -WarningAction SilentlyContinue `
                        -ErrorVariable errors -ErrorAction SilentlyContinue
                )

                $global:newDbaSsisCatalogServiceLookups |
                    Should -Be 2 -Because "result=$($result.Count); warnings=$($warnings -join ' | '); errors=$($errors -join ' | ')"
                $global:newDbaSsisCatalogFallbackLookups | Should -Be 1
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Refuses in the begin block without creating a catalog" {
        It "warns and creates nothing when no password or credential is supplied" {
            $splatNoPassword = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(New-DbaSsisCatalog @splatNoPassword)
            $result.Count | Should -Be 0
            $warn.Count | Should -BeGreaterThan 0

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $expected = if ($PSVersionTable.PSEdition -eq "Core") {
                "This command is not supported on Linux or macOS"
            } else {
                "You must specify either -SecurePassword or -Credential"
            }
            $payload | Should -Be $expected
        }
    }

    if ($PSVersionTable.PSEdition -eq "Desktop") {
        Context "Creates the SSIS catalog on the SSIS fixture" {
            BeforeAll {
                $ssisInstance = $TestConfig.InstanceSsis
                $ssisPassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

                function Get-SsisCatalogCount {
                    $query = "SELECT COUNT(*) AS CatalogCount FROM sys.databases WHERE name = N'SSISDB'"
                    [int](Invoke-DbaQuery -SqlInstance $ssisInstance -Database master -Query $query -EnableException).CatalogCount
                }

                function New-IndependentSsisCatalog {
                    $server = Connect-DbaInstance -SqlInstance $ssisInstance -MinimumVersion 10
                    $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
                    $passwordPointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ssisPassword)
                    try {
                        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordPointer)
                        $catalog = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog (
                            $ssis,
                            "SSISDB",
                            $plainPassword
                        )
                        $catalog.Create()
                    } finally {
                        $plainPassword = $null
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
                    }
                }

                function Remove-SsisCatalog {
                    if ((Get-SsisCatalogCount) -gt 0) {
                        Remove-DbaDatabase -SqlInstance $ssisInstance -Database SSISDB -Confirm:$false -EnableException
                    }
                }
            }

            AfterAll {
                if ((Get-SsisCatalogCount) -eq 0) {
                    New-IndependentSsisCatalog
                }
                Get-SsisCatalogCount | Should -Be 1
            }

            It "honors WhatIf and then creates the catalog on the same target" {
                Remove-SsisCatalog
                Get-SsisCatalogCount | Should -Be 0

                $whatIfResult = @(New-DbaSsisCatalog -SqlInstance $ssisInstance -SecurePassword $ssisPassword -WhatIf)
                $whatIfResult.Count | Should -Be 0
                Get-SsisCatalogCount | Should -Be 0

                $result = @(New-DbaSsisCatalog -SqlInstance $ssisInstance -SecurePassword $ssisPassword -Confirm:$false)
                $result.Count | Should -Be 1
                $result[0].Created | Should -BeTrue
                $result[0].SsisCatalog | Should -Be "SSISDB"
                $result[0].SqlInstance | Should -BeLike "*$ssisInstance*"
                Get-SsisCatalogCount | Should -Be 1
            }
        }
    }
}
