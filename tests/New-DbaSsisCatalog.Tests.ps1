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
}

Describe $CommandName -Tag IntegrationTests {
    Context "Catalog is added properly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # database name is currently fixed
            $database = "SSISDB"
            $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database
            $results = $null
            $shouldRunTests = $false

            if (-not $db) {
                $password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
                $results = New-DbaSsisCatalog -SqlInstance $TestConfig.InstanceSingle -Password $password -WarningAction SilentlyContinue -WarningVariable warn

                # Run the tests only if it worked (this could be more accurate but w/e, it's hard to test on appveyor)
                if ($warn -match "not running") {
                    if (-not $env:APPVEYOR_REPO_BRANCH) {
                        Write-Warning "$warn"
                    }
                    $shouldRunTests = $false
                } else {
                    $shouldRunTests = $true
                }
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup the created catalog if it exists
            if ($shouldRunTests -and $database) {
                Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "uses the specified database" -Skip:(-not $shouldRunTests) {
            $results.SsisCatalog | Should -Be $database
        }

        It "creates the catalog" -Skip:(-not $shouldRunTests) {
            $results.Created | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # database name is currently fixed
            $database = "SSISDB"
            $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database
            $result = $null
            $shouldRunTests = $false

            if (-not $db) {
                $password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
                $result = New-DbaSsisCatalog -SqlInstance $TestConfig.InstanceSingle -Password $password -WarningAction SilentlyContinue -WarningVariable warn

                # Run the tests only if it worked (this could be more accurate but w/e, it's hard to test on appveyor)
                if ($warn -match "not running") {
                    if (-not $env:APPVEYOR_REPO_BRANCH) {
                        Write-Warning "$warn"
                    }
                    $shouldRunTests = $false
                } else {
                    $shouldRunTests = $true
                }
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup the created catalog if it exists
            if ($shouldRunTests -and $database) {
                Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" -Skip:(-not $shouldRunTests) {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" -Skip:(-not $shouldRunTests) {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SsisCatalog',
                'Created'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}