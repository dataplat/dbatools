#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaFirstResponderKit",
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
                "Branch",
                "Database",
                "LocalFile",
                "OnlyScript",
                "LetPublicExecute",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Testing First Responder Kit installer with download" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database -Branch main -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status -eq "Installed" | Should -Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            "sp_Blitz", "sp_BlitzIndex" | Should -BeIn $resultsDownload.Name
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database
            $resultsDownload[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database -WarningAction SilentlyContinue
            $result[0].Status -eq "Error" | Should -Be $true
        }
    }

    Context "Testing First Responder Kit installer with LocalFile" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Type Container -Path $tempDir

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            $server.Query("CREATE DATABASE $database")

            $outfile = "$tempDir\SQL-Server-First-Responder-Kit-main.zip"
            Invoke-WebRequest -Uri "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/main.zip" -OutFile $outfile
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database -Branch main -LocalFile $outfile -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $database

            Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status -eq "Installed" | Should -Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            "sp_Blitz", "sp_BlitzIndex" | Should -BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database
            $resultsLocalFile[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database -WarningAction SilentlyContinue
            $result[0].Status -eq "Error" | Should -Be $true
        }
    }

    Context "Testing certificate signing in user database" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $server.Query("CREATE DATABASE $database")

            # Each context uses its own login so that a context whose AfterAll does not complete cannot fail the next one with "already exists".
            $loginName = "AsGoodAsPublic_$(Get-Random)"
            $queryCreateLogin = @"
CREATE LOGIN [$loginName] WITH PASSWORD = '<enterStrongPasswordHere>';
"@
            $server.Query($queryCreateLogin)
            $password = ConvertTo-SecureString "<enterStrongPasswordHere>" -AsPlainText -Force
            $public = New-Object System.Management.Automation.PSCredential($loginName, $password)

            $splatFirstResponderKit = @{
                SqlInstance      = $TestConfig.InstanceMulti1
                Database         = $database
                Branch           = "main"
                Force            = $true
                LetPublicExecute = @("sp_BlitzFirst", "sp_BlitzIndex")
            }
            $null = Install-DbaFirstResponderKit @splatFirstResponderKit

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $database
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $loginName -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Lets public execute sp_BlitzFirst when signed for" {
            $splatPublicBlitzFirst = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_BlitzFirst @SinceStartup = 1;"
                SqlCredential   = $public
                EnableException = $true
            }
            { Invoke-DbaQuery @splatPublicBlitzFirst } | Should -Not -Throw
        }

        It "Does not let public execute sp_Blitz when not signed for" {
            $splatPublicBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz;"
                SqlCredential   = $public
                EnableException = $true
            }
            # The login can connect to the database because LetPublicExecute granted CONNECT to public,
            # so the only thing that may stop it is the missing EXECUTE permission on the unsigned procedure.
            { Invoke-DbaQuery @splatPublicBlitz } | Should -Throw -ExpectedMessage "*EXECUTE permission*"
        }

        It "Lets admin execute sp_Blitz when not signed for" {
            $splatAdminBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz @Help = 1"
                EnableException = $true
            }
            { Invoke-DbaQuery @splatAdminBlitz } | Should -Not -Throw
        }
    }

    Context "Testing without certificate signing" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $server.Query("CREATE DATABASE $database")

            # Each context uses its own login so that a context whose AfterAll does not complete cannot fail the next one with "already exists".
            $loginName = "AsGoodAsPublic_$(Get-Random)"
            $queryCreateLogin = @"
CREATE LOGIN [$loginName] WITH PASSWORD = '<enterStrongPasswordHere>';
"@
            $server.Query($queryCreateLogin)
            $password = ConvertTo-SecureString "<enterStrongPasswordHere>" -AsPlainText -Force
            $public = New-Object System.Management.Automation.PSCredential($loginName, $password)

            $splatFirstResponderKit = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $database
                Branch      = "main"
                Force       = $true
            }
            $null = Install-DbaFirstResponderKit @splatFirstResponderKit

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $database
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $loginName -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # Without LetPublicExecute the command never grants CONNECT to public, so the login is stopped
        # one step earlier than in the signing contexts: it cannot open the database at all.
        # Asserting that message still proves the login exists and authenticated, which a bare
        # Should -Throw would not - a wrong password fails with "Login failed for user" instead.
        It "Does not let public execute sp_BlitzFirst" {
            $splatPublicBlitzFirst = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_BlitzFirst @SinceStartup = 1;"
                SqlCredential   = $public
                EnableException = $true
            }
            { Invoke-DbaQuery @splatPublicBlitzFirst } | Should -Throw -ExpectedMessage "*Cannot open database*"
        }

        It "Does not let public execute sp_Blitz" {
            $splatPublicBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz;"
                SqlCredential   = $public
                EnableException = $true
            }
            { Invoke-DbaQuery @splatPublicBlitz } | Should -Throw -ExpectedMessage "*Cannot open database*"
        }

        It "Lets admin execute sp_Blitz" {
            $splatAdminBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz @Help = 1"
                EnableException = $true
            }
            { Invoke-DbaQuery @splatAdminBlitz } | Should -Not -Throw
        }
    }

    Context "Testing certificate signing in master database" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $database = "master"

            # Each context uses its own login so that a context whose AfterAll does not complete cannot fail the next one with "already exists".
            $loginName = "AsGoodAsPublic_$(Get-Random)"
            $queryCreateLogin = @"
CREATE LOGIN [$loginName] WITH PASSWORD = '<enterStrongPasswordHere>';
"@
            $server.Query($queryCreateLogin)
            $password = ConvertTo-SecureString "<enterStrongPasswordHere>" -AsPlainText -Force
            $public = New-Object System.Management.Automation.PSCredential($loginName, $password)

            $splatFirstResponderKit = @{
                SqlInstance      = $TestConfig.InstanceMulti1
                Database         = $database
                Branch           = "main"
                Force            = $true
                LetPublicExecute = @("sp_BlitzFirst", "sp_BlitzIndex")
            }
            $null = Install-DbaFirstResponderKit @splatFirstResponderKit

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $loginName -Force
            Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -OnlyScript Uninstall.sql

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Lets public execute sp_BlitzFirst when signed for" {
            $splatPublicBlitzFirst = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_BlitzFirst @SinceStartup = 1;"
                SqlCredential   = $public
                EnableException = $true
            }
            { Invoke-DbaQuery @splatPublicBlitzFirst } | Should -Not -Throw
        }

        It "Does not let public execute sp_Blitz when not signed for" {
            $splatPublicBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz;"
                SqlCredential   = $public
                EnableException = $true
            }
            # Every login can reach master through guest, so the missing EXECUTE permission on the
            # unsigned procedure is the only thing that can stop it here.
            { Invoke-DbaQuery @splatPublicBlitz } | Should -Throw -ExpectedMessage "*EXECUTE permission*"
        }

        It "Lets admin execute sp_Blitz when not signed for" {
            $splatAdminBlitz = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = $database
                Query           = "EXECUTE sp_Blitz @Help = 1"
                EnableException = $true
            }
            { Invoke-DbaQuery @splatAdminBlitz } | Should -Not -Throw
        }
    }
}
