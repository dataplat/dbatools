param($ModuleName = 'dbatools')

Describe "Export-DbaUser Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaUser
        }

        It "has all the required parameters" {
            $params = @(
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
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Export-DbaUser Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputPath = "$AltExportPath\Dbatoolsci_user_CustomFolder"
        $outputFile = "$AltExportPath\Dbatoolsci_user_CustomFile.sql"
        $outputFile2 = "$AltExportPath\Dbatoolsci_user_CustomFile2.sql"

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

        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $null = $server.Query("CREATE DATABASE [$dbname]")

        $securePassword = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $login -Password $securePassword
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $login2 -Password $securePassword
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $login01 -Password $securePassword
        $null = New-DbaLogin -SqlInstance $global:instance1 -Login $login02 -Password $securePassword

        $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname
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
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance1 -Login $login -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance1 -Login $login2 -Confirm:$false
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
        Remove-Item -Path $outputFile2 -ErrorAction SilentlyContinue
        Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue -Confirm:$false
    }

    Context "Check if output file was created" {
        BeforeAll {
            $userExists = Get-DbaDbUser -SqlInstance $global:instance1 -Database $dbname | Where-Object Name -eq $user
            if ($userExists) {
                $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -User $user -FilePath $outputFile
            }
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Respects options specified in the ScriptingOptionsObject parameter" {
        It 'Excludes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $false
            $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -Not -BeLike ('*USE `[' + $dbname + '`]*')
        }

        It 'Includes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $true
            $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -BeLike ('*USE `[' + $dbname + '`]*')
        }

        It 'Defaults to include database context' {
            $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should -BeLike ('*USE `[' + $dbname + '`]*')
        }

        It 'Exports as template' {
            $results = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -User $user -Template -DestinationVersion SQLServer2016 -WarningAction SilentlyContinue -Passthru
            $results | Should -BeLike "*CREATE USER ``[{templateUser}``] FOR LOGIN ``[{templateLogin}``]*"
            $results | Should -BeLike "*GRANT SELECT ON OBJECT::``[dbo``].``[$table``] TO ``[{templateUser}``]*"
            $results | Should -BeLike "*ALTER ROLE ``[$role``] ADD MEMBER ``[{templateUser}``]*"
        }
    }

    Context "Check if one output file per user was created" {
        BeforeAll {
            $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -Path $outputPath
        }

        It "Exports files to the path" {
            $userCount = (Get-DbaDbUser -SqlInstance $global:instance1 -Database $dbname | Where-Object { $_.Name -notin @("dbo", "guest", "sys", "INFORMATION_SCHEMA") } | Measure-Object).Count
            (Get-ChildItem $outputPath).Count | Should -Be $userCount
        }

        It "Exported file name contains username '$user'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User + '*') | Should -BeTrue
        }

        It "Exported file name contains username '$user2'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User2 + '*') | Should -BeTrue
        }
    }

    Context "Check if the output scripts were self-contained" {
        BeforeAll {
            Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue
            $null = Export-DbaUser -SqlInstance $global:instance1 -Database $dbname -Path $outputPath
        }

        It "Contains the CREATE ROLE and ALTER ROLE statements for its own roles" {
            $user01Content = Get-Content -Path (Get-ChildItem $outputPath | Where-Object Name -like ('*' + $user01 + '*')).FullName -Raw
            $user01Content | Should -BeLike "*CREATE ROLE [[]$role01]*"
            $user01Content | Should -BeLike "*CREATE ROLE [[]$role02]*"
            $user01Content | Should -Not -BeLike "*CREATE ROLE [[]$role03]*"
            $user01Content | Should -BeLike "*ALTER ROLE [[]$role01] ADD MEMBER [[]$user01]*"
            $user01Content | Should -BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user01]*"
            $user01Content | Should -Not -BeLike "*ALTER ROLE [[]$role03]*"

            $user02Content = Get-Content -Path (Get-ChildItem $outputPath | Where-Object Name -like ('*' + $user02 + '*')).FullName -Raw
            $user02Content | Should -BeLike "*CREATE ROLE [[]$role02]*"
            $user02Content | Should -BeLike "*CREATE ROLE [[]$role03]*"
            $user02Content | Should -Not -BeLike "*CREATE ROLE [[]$role01]*"
            $user02Content | Should -BeLike "*ALTER ROLE [[]$role02] ADD MEMBER [[]$user02]*"
            $user02Content | Should -BeLike "*ALTER ROLE [[]$role03] ADD MEMBER [[]$user02]*"
            $user02Content | Should -Not -BeLike "*ALTER ROLE [[]$role01]*"
        }
    }
}
