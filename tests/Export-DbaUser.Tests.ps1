$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
$PSDefaultParameterValues = $TestConfig.Defaults

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'User', 'DestinationVersion', 'Encoding', 'Path', 'FilePath', 'InputObject', 'NoClobber', 'Append', 'EnableException', 'ScriptingOptionsObject', 'ExcludeGoBatchSeparator', 'Passthru', 'Template'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $outputPath = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFolder"
        $outputFile = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFile.sql"
        $outputFile2 = "$($TestConfig.Temp)\Dbatoolsci_user_CustomFile2.sql"
        try {
            $dbname = "dbatoolsci_exportdbauser"
            $login = "dbatoolsci_exportdbauser_login"
            $login2 = "dbatoolsci_exportdbauser_login2"
            $user = "dbatoolsci_exportdbauser_user"
            $user2 = "dbatoolsci_exportdbauser_user2"
            $table = "dbatoolsci_exportdbauser_table"
            $role = "dbatoolsci_exportdbauser_role"

            # For Dependencies elimination test
            $login01 = "dbatoolsci_exportdbauser_login01"
            $login02 = "dbatoolsci_exportdbauser_login02"
            $user01 = "dbatoolsci_exportdbauser_user01"
            $user02 = "dbatoolsci_exportdbauser_user02"
            $role01 = "dbatoolsci_exportdbauser_role01"
            $role02 = "dbatoolsci_exportdbauser_role02"
            $role03 = "dbatoolsci_exportdbauser_role03"

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
            $null = $db.Query("EXEC sp_addrolemember '$role01', '$user01';")
            $null = $db.Query("EXEC sp_addrolemember '$role02', '$user01';")
            $null = $db.Query("EXEC sp_addrolemember '$role02', '$user02';")
            $null = $db.Query("EXEC sp_addrolemember '$role03', '$user02';")
            $null = $db.Query("GRANT SELECT ON OBJECT::$table TO [$user2];")
        } catch { } # No idea why appveyor can't handle this
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
        Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login, $login2, $login01, $login02
        (Get-ChildItem $outputFile -ErrorAction SilentlyContinue) | Remove-Item
        (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item
        Remove-Item -Path $outputPath -Recurse
    }

    Context "Check if output file was created" {
        if (Get-DbaDbUser -SqlInstance $TestConfig.instance1 -Database $dbname | Where-Object Name -eq $user) {
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -FilePath $outputFile
            It "Exports results to one sql file" {
                (Get-ChildItem $outputFile).Count | Should Be 1
            }
            It "Exported file is bigger than 0" {
                (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
            }
        }
    }

    Context "Respects options specified in the ScriptingOptionsObject parameter" {
        It 'Excludes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $false
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should Not BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Includes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $true
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Defaults to include database context' {
            $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Exports as template' {
            $results = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -User $user -Template -DestinationVersion SQLServer2016 -WarningAction SilentlyContinue -Passthru
            $results | Should BeLike "*CREATE USER ``[{templateUser}``] FOR LOGIN ``[{templateLogin}``]*"
            $results | Should BeLike "*GRANT SELECT ON OBJECT::``[dbo``].``[$table``] TO ``[{templateUser}``]*"
            $results | Should BeLike "*ALTER ROLE ``[$role``] ADD MEMBER ``[{templateUser}``]*"
        }
    }

    Context "Check if one output file per user was created" {
        $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -Path $outputPath
        It "Exports files to the path" {
            $userCount = (Get-DbaDbUser -SqlInstance $TestConfig.instance1 -Database $dbname | Where-Object { $_.Name -notin @("dbo", "guest", "sys", "INFORMATION_SCHEMA") } | Measure-Object).Count
            (Get-ChildItem $outputPath).Count | Should Be $userCount
        }
        It "Exported file name contains username '$user'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User + '*') | Should BeTrue
        }
        It "Exported file name contains username '$user2'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User2 + '*') | Should BeTrue
        }
    }

    Context "Check if the output scripts were self-contained" {
        # Clean up the output folder
        Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
        $null = Export-DbaUser -SqlInstance $TestConfig.instance1 -Database $dbname -Path $outputPath

        It "Contains the CREATE ROLE and ALTER ROLE statements for its own roles" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $user01 + '*') | ForEach-Object {
                $content = Get-Content -Path $_.FullName -Raw
                $content | Should BeLike "*CREATE ROLE [[]$role01]*"
                $content | Should BeLike "*CREATE ROLE [[]$role02]*"
                $content | Should Not BeLike "*CREATE ROLE [[]$role03]*"

                $content | Should BeLike "*ALTER ROLE [[]$role01] ADD MEMBER [[]$user01]*"
                $content | Should BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user01]*"
                $content | Should Not BeLike "*ALTER ROLE [[]$role03]*"
            }

            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $user02 + '*') | ForEach-Object {
                $content = Get-Content -Path $_.FullName -Raw
                $content | Should BeLike "*CREATE ROLE [[]$role02]*"
                $content | Should BeLike "*CREATE ROLE [[]$role03]*"
                $content | Should Not BeLike "*CREATE ROLE [[]$role01]*"

                $content | Should BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user02]*"
                $content | Should BeLike "*ALTER ROLE [[]$role03] ADD MEMBER [[]$user02]*"
                $content | Should Not BeLike "*ALTER ROLE [[]$role01]*"
            }
        }
    }
}
