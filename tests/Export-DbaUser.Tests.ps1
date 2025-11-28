#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "InputObject",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "User",
                "DestinationVersion",
                "Path",
                "FilePath",
                "Encoding",
                "NoClobber",
                "Append",
                "Passthru",
                "Template",
                "EnableException",
                "ScriptingOptionsObject",
                "ExcludeGoBatchSeparator"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test user export, we need a database with users, logins, roles, and permissions.
        # For testing role dependencies, we need multiple users and roles with complex relationships.

        # Set variables. They are available in all the It blocks.
        $dbname = "dbatoolsci_exportdbauser"
        $login = "dbatoolsci_exportdbauser_login"
        $login2 = "dbatoolsci_exportdbauser_login2"
        $user = "dbatoolsci_exportdbauser_user"
        $user2 = "dbatoolsci_exportdbauser_user2"
        $table = "dbatoolsci_exportdbauser_table"
        $role = "dbatoolsci_exportdbauser_role"
        $schema = "dbatoolsci_exportdbauser_schema"

        $outputPath = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFolder"
        $outputFile = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFile.sql"
        $outputFile2 = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFile2.sql"

        # For Dependencies elimination test
        $login01 = "dbatoolsci_exportdbauser_login01"
        $login02 = "dbatoolsci_exportdbauser_login02"
        $user01 = "dbatoolsci_exportdbauser_user01"
        $user02 = "dbatoolsci_exportdbauser_user02"
        $role01 = "dbatoolsci_exportdbauser_role01"
        $role02 = "dbatoolsci_exportdbauser_role02"
        $role03 = "dbatoolsci_exportdbauser_role03"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $null = $server.Query("CREATE DATABASE [$dbname]")

        $securePassword = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
        $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login -Password $securePassword
        $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login2 -Password $securePassword
        $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login01 -Password $securePassword
        $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login02 -Password $securePassword

        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
        $null = $db.Query("CREATE USER [$user] FOR LOGIN [$login]")
        $null = $db.Query("CREATE USER [$user2] FOR LOGIN [$login2]")
        $null = $db.Query("CREATE USER [$user01] FOR LOGIN [$login01]")
        $null = $db.Query("CREATE USER [$user02] FOR LOGIN [$login02]")
        $null = $db.Query("CREATE ROLE [$role]")
        $null = $db.Query("CREATE ROLE [$role01]")
        $null = $db.Query("CREATE ROLE [$role02]")
        $null = $db.Query("CREATE ROLE [$role03]")

        $null = $db.Query("CREATE TABLE $table (C1 INT);")
        $null = $db.Query("GRANT SELECT ON OBJECT::$table TO [$user];")
        $null = $db.Query("EXEC sp_addrolemember '$role', '$user';")
        $null = $db.Query("CREATE SCHEMA [$schema] AUTHORIZATION [$user];")
        $null = $db.Query("EXEC sp_addrolemember '$role01', '$user01';")
        $null = $db.Query("EXEC sp_addrolemember '$role02', '$user01';")
        $null = $db.Query("EXEC sp_addrolemember '$role02', '$user02';")
        $null = $db.Query("EXEC sp_addrolemember '$role03', '$user02';")
        $null = $db.Query("GRANT SELECT ON OBJECT::$table TO [$user2];")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login, $login2, $login01, $login02

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse
        Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
        Remove-Item -Path $outputFile2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            @(Get-ChildItem $outputFile).Count | Should -BeExactly 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Respects options specified in the ScriptingOptionsObject parameter" {
        It "Excludes database context" {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $false
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -Not -Match ([regex]::Escape("USE [$dbname]"))
            Remove-Item -Path $outputFile2 -ErrorAction SilentlyContinue
        }

        It "Includes database context" {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $true
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -Match ([regex]::Escape("USE [$dbname]"))
            Remove-Item -Path $outputFile2 -ErrorAction SilentlyContinue
        }

        It "Defaults to include database context" {
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -FilePath $outputFile2
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -Match ([regex]::Escape("USE [$dbname]"))
            Remove-Item -Path $outputFile2 -ErrorAction SilentlyContinue
        }

        It "Exports as template" {
            $results = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -Template -DestinationVersion SQLServer2016 -WarningAction SilentlyContinue -Passthru
            $results | Should -BeLike "*CREATE USER ``[{templateUser}``] FOR LOGIN ``[{templateLogin}``]*"
            $results | Should -BeLike "*GRANT SELECT ON OBJECT::``[dbo``].``[$table``] TO ``[{templateUser}``]*"
            $results | Should -BeLike "*ALTER ROLE ``[$role``] ADD MEMBER ``[{templateUser}``]*"
        }
    }

    Context "Check if one output file per user was created" {
        BeforeAll {
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -Path $outputPath
            $exportedFiles = @(Get-ChildItem $outputPath)
            $userCount = @(Get-DbaDbUser -SqlInstance $TestConfig.instance1 -Database $dbname | Where-Object { $PSItem.Name -notin @("dbo", "guest", "sys", "INFORMATION_SCHEMA") }).Count
        }

        It "Exports files to the path" {
            $exportedFiles.Count | Should -BeExactly $userCount
        }

        It "Exported file name contains username '$user'" {
            $exportedFiles | Where-Object Name -like ("*" + $user + "*") | Should -Not -BeNullOrEmpty
        }

        It "Exported file name contains username '$user2'" {
            $exportedFiles | Where-Object Name -like ("*" + $user2 + "*") | Should -Not -BeNullOrEmpty
        }
    }

    Context "Check if the output scripts were self-contained" {
        It "Contains the CREATE ROLE and ALTER ROLE statements for its own roles" {
            # Clean up the output folder
            Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -Path $outputPath
            Get-ChildItem $outputPath | Where-Object Name -like ("*" + $user01 + "*") | ForEach-Object {
                $content = Get-Content -Path $PSItem.FullName -Raw
                $content | Should -BeLike "*CREATE ROLE [[]$role01]*"
                $content | Should -BeLike "*CREATE ROLE [[]$role02]*"
                $content | Should -Not -BeLike "*CREATE ROLE [[]$role03]*"

                $content | Should -BeLike "*ALTER ROLE [[]$role01] ADD MEMBER [[]$user01]*"
                $content | Should -BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user01]*"
                $content | Should -Not -BeLike "*ALTER ROLE [[]$role03]*"
            }

            Get-ChildItem $outputPath | Where-Object Name -like ("*" + $user02 + "*") | ForEach-Object {
                $content = Get-Content -Path $PSItem.FullName -Raw
                $content | Should -BeLike "*CREATE ROLE [[]$role02]*"
                $content | Should -BeLike "*CREATE ROLE [[]$role03]*"
                $content | Should -Not -BeLike "*CREATE ROLE [[]$role01]*"

                $content | Should -BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user02]*"
                $content | Should -BeLike "*ALTER ROLE [[]$role03] ADD MEMBER [[]$user02]*"
                $content | Should -Not -BeLike "*ALTER ROLE [[]$role01]*"
            }
        }
    }

    Context "Schema ownership" {
        It "Exports schema ownership for users that own schemas" {
            $results = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -Passthru
            $results | Should -BeLike "*ALTER AUTHORIZATION ON SCHEMA::[[]$schema] TO [[]$user]*"
        }

        It "Exports schema ownership with template placeholders" {
            $results = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -Template -Passthru
            $results | Should -BeLike "*ALTER AUTHORIZATION ON SCHEMA::[[]$schema] TO [[]``{templateUser``}]*"
        }
    }
}