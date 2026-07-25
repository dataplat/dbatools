#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaServerRole",
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
                "InputObject",
                "ScriptingOptionsObject",
                "ServerRole",
                "ExcludeServerRole",
                "ExcludeFixedRole",
                "IncludeRoleMember",
                "Path",
                "FilePath",
                "Passthru",
                "BatchSeparator",
                "NoClobber",
                "Append",
                "NoPrefix",
                "Encoding",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Multiple piped records" {
        It "does not re-emit the prior role when the current record produces no SQL" {
            Mock Get-DbaServerRole -ModuleName dbatools {
                param($SqlInstance)

                $name = @($SqlInstance)[0].ToString()
                $version = if ($name -eq "instance-1") { 15 } else { 10 }
                $server = [pscustomobject]@{
                    ServerType  = "Standalone"
                    VersionMajor = $version
                }
                $server | Add-Member -MemberType ScriptMethod -Name Query -Value { param($query) @() }
                $role = [pscustomobject]@{
                    Name        = "role-$name"
                    SqlInstance = $name
                    Parent      = $server
                    Login       = @()
                    Role        = "role-$name"
                }
                $role | Add-Member -MemberType ScriptMethod -Name Script -Value {
                    param($options)
                    @("CREATE SERVER ROLE [$($this.Name)]")
                }
                $role
            }

            $instances = @(
                [Dataplat.Dbatools.Parameter.DbaInstanceParameter]::new("instance-1")
                [Dataplat.Dbatools.Parameter.DbaInstanceParameter]::new("instance-2")
            )
            $options = [Microsoft.SqlServer.Management.Smo.ScriptingOptions]::new()
            $result = @($instances | Export-DbaServerRole -ScriptingOptionsObject $options -Passthru -NoPrefix -BatchSeparator "")

            @($result | Where-Object { $_ -match "role-instance-1" }).Count | Should -BeExactly 1
            @($result | Where-Object { $_ -match "role-instance-2" }).Count | Should -BeExactly 0
            Should -Invoke Get-DbaServerRole -ModuleName dbatools -Times 2 -Exactly
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create a directory for test output files
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_ServerRole.sql"

        # Create test objects
        $random = Get-Random
        $login1 = "dbatoolsci_exportdbaserverrole_login1$random"
        $svRole = "dbatoolsci_ScriptPermissions$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("CREATE SERVER ROLE [$svRole] AUTHORIZATION [$login1]")
        $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]")
        $null = $server.Query("GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]")
        $null = $server.Query("DENY SELECT ALL USER SECURABLES TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DEFINITION TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DATABASE TO [$svRole]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $svRole
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1

        # Remove test files
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check using piped input created" {
        BeforeAll {
            $role = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole $svRole
            $null = $role | Export-DbaServerRole -FilePath $outputFile
            $results = $role | Export-DbaServerRole -Passthru
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            $results -match "GO" | Should -BeTrue
        }

        It "should include the role" {
            $results -match "CREATE SERVER ROLE \[$svRole\]" | Should -BeTrue
        }

        It "should include ADD MEMBER" {
            $results -match "ALTER SERVER ROLE \[dbcreator\] ADD MEMBER \[$svRole\]" | Should -BeTrue
        }

        It "should include GRANT CREATE TRACE EVENT" {
            $results -match "GRANT CREATE TRACE EVENT NOTIFICATION TO \[$svRole\]" | Should -BeTrue
        }

        It "should include DENY SELECT ALL USER SECURABLES" {
            $results -match "DENY SELECT ALL USER SECURABLES TO \[$svRole\]" | Should -BeTrue
        }

        It "should include VIEW ANY DEFINITION" {
            $results -match "GRANT VIEW ANY DEFINITION TO \[$svRole\];" | Should -BeTrue
        }

        It "should include GRANT VIEW ANY DATABASE" {
            $results -match "GRANT VIEW ANY DATABASE TO \[$svRole\];" | Should -BeTrue
        }
    }
}
