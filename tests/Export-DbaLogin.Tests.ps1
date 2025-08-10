#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Export-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "Login",
                "ExcludeLogin",
                "Database",
                "ExcludeJobs",
                "ExcludeDatabase",
                "ExcludePassword",
                "DefaultDatabase",
                "Path",
                "FilePath",
                "Encoding",
                "NoClobber",
                "Append",
                "BatchSeparator",
                "DestinationVersion",
                "NoPrefix",
                "Passthru",
                "ObjectLevel",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $global:DefaultExportPath = Get-DbatoolsConfigValue -FullName path.dbatoolsexport
        $global:AltExportPath = "$env:USERPROFILE\Documents"
        $global:random = Get-Random
        $global:dbname1 = "dbatoolsci_exportdbalogin1$global:random"
        $global:login1 = "dbatoolsci_exportdbalogin_login1$global:random"
        $global:user1 = "dbatoolsci_exportdbalogin_user1$global:random"

        $global:dbname2 = "dbatoolsci_exportdbalogin2$global:random"
        $global:login2 = "dbatoolsci_exportdbalogin_login2$global:random"
        $global:user2 = "dbatoolsci_exportdbalogin_user2$global:random"

        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:db1 = New-DbaDatabase -SqlInstance $global:server -Name $global:dbname1
        $null = $global:server.Query("CREATE LOGIN [$global:login1] WITH PASSWORD = 'GoodPass1234!'")
        $global:db1.Query("CREATE USER [$global:user1] FOR LOGIN [$global:login1]")

        $global:db2 = New-DbaDatabase -SqlInstance $global:server -Name $global:dbname2
        $null = $global:server.Query("CREATE LOGIN [$global:login2] WITH PASSWORD = 'GoodPass1234!'")
        $null = $global:server.Query("ALTER LOGIN [$global:login2] DISABLE")
        $null = $global:server.Query("DENY CONNECT SQL TO [$global:login2]")

        if ($global:server.VersionMajor -lt 11) {
            $null = $global:server.Query("EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$global:login2'")
        } else {
            $null = $global:server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$global:login2]")
        }
        $global:db2.Query("CREATE USER [$global:user2] FOR LOGIN [$global:login2]")
        $global:db2.Query("GRANT SELECT ON sys.tables TO [$global:user2] WITH GRANT OPTION")

        # login and user that have the same name but aren't linked
        $global:login3 = "dbatoolsci_exportdbalogin_login3$global:random"
        $global:server.Query("CREATE LOGIN [$global:login3] WITH PASSWORD = 'GoodPass1234!'")
        $global:db1.Query("CREATE USER [$global:login3] WITHOUT LOGIN")

        $global:allfiles = @()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbname1 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login1 -Confirm:$false -ErrorAction SilentlyContinue

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbname2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login3 -Confirm:$false -ErrorAction SilentlyContinue

        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedCredential = Get-ChildItem $global:DefaultExportPath, $global:AltExportPath -ErrorAction SilentlyContinue | Where-Object Name -match "$timenow\d{4}-login.sql|Dbatoolsci_login_CustomFile.sql"
        if ($ExportedCredential) {
            $null = Remove-Item -Path $($ExportedCredential.FullName) -ErrorAction SilentlyContinue
        }

        # Remove any additional files that were created during testing
        if ($global:allfiles) {
            Remove-Item -Path $global:allfiles -ErrorAction SilentlyContinue
        }
    }

    Context "Executes with Exclude Parameters" {
        It "Should exclude databases when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Match "\nGo\r"
        }

        It "Should exclude Jobs when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeJobs -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Not -Match "Job"
        }

        It "Should exclude Go when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -BatchSeparator "" -ObjectLevel -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Not -Match "GO"
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$global:user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$global:user2\] FOR LOGIN \[$global:login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$global:dbname2\]"
        }

        It "Should exclude a specific login" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeLogin $global:login1 -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Not -Match "$global:login1"
        }

        It "Should exclude passwords" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeLogin $global:login1 -WarningAction SilentlyContinue -ExcludePassword
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Not -Match "(?<=PASSWORD =\s0x)(\w+)"
        }
    }
    Context "Executes for various users, databases, and environments" {
        It "Should Export a specific user" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login1 -Database $global:dbname1 -DefaultDatabase master -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $global:allfiles += $file.FullName
            $results | Should -Not -Match "$global:login2|$global:dbname2"
            $results | Should -Match "$global:login1|$global:dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$global:user1')"))
        }

        It "Should Export with object level permissions" {
            $results = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login2 -ObjectLevel -PassThru -WarningAction SilentlyContinue
            $results | Should -Not -Match "$global:login1|$global:dbname1"
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$global:user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$global:user2\] FOR LOGIN \[$global:login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$global:dbname2\]"
        }

        foreach ($version in $((Get-Command $CommandName).Parameters.DestinationVersion.attributes.validvalues)) {
            It "Should Export for the SQLVersion $version" {
                $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $global:login2 -Database $global:dbname2 -DestinationVersion $version -WarningAction SilentlyContinue
                $results = Get-Content -Path $file -Raw
                $global:allfiles += $file.FullName
                $results | Should -Match "$global:login2|$global:dbname2"
                $results | Should -Not -Match "$global:login1|$global:dbname1"
            }
        }

        It "Should Export only logins from the db that is piped in" {
            $file = $global:db1 | Export-DbaLogin
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match "$global:login2|$global:dbname2|$global:login3"
            $results | Should -Match "$global:login1|$global:dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$global:user1')"))
        }
    }
    Context "Exports file to random and specified paths" {
        It "Should export file to the configured path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $global:allfiles += $file.FullName
            $results | Should -Be $global:DefaultExportPath
        }

        It "Should export file to custom folder path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Path $global:AltExportPath -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $global:allfiles += $file.FullName
            $results | Should -Be $global:AltExportPath
        }

        It "Should export file to custom file path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$global:AltExportPath\Dbatoolsci_login_CustomFile.sql" -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.Name
            $global:allfiles += $file.FullName
            $results | Should -Be "Dbatoolsci_login_CustomFile.sql"
        }

        It "Should export file to custom file path and Append" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$global:AltExportPath\Dbatoolsci_login_CustomFile.sql" -Append -ExcludeDatabase -WarningAction SilentlyContinue
            $global:allfiles += $file.FullName
            $file.CreationTimeUtc.Ticks | Should -BeLessThan $file.LastWriteTimeUtc.Ticks
        }

        It "Should not export file to custom file path with NoClobber" {
            { Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$global:AltExportPath\Dbatoolsci_login_CustomFile.sql" -NoClobber -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}