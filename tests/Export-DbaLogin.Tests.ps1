#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Export-DbaLogin",
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
                "IncludeRolePermissions",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "IncludeRolePermissions scripting" {
        BeforeAll {
            if (-not ("ExportDbaLoginRoleTest.MockServer" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Collections;
using System.Collections.Generic;

namespace ExportDbaLoginRoleTest {
    public class MockCollection<T> : IEnumerable {
        private Dictionary<string, T> items = new Dictionary<string, T>(StringComparer.OrdinalIgnoreCase);

        public void Add(string name, T item) {
            items[name] = item;
        }

        public T this[string name] {
            get { return items[name]; }
        }

        public IEnumerator GetEnumerator() {
            return items.Values.GetEnumerator();
        }
    }

    public class MockMapping {
        public string DBName { get; set; }
        public string UserName { get; set; }
        public string LoginName { get; set; }
    }

    public class MockUser {
        public string Name { get; set; }
        public string[] Scripts { get; set; }

        public string[] Script(object scriptingOptions) {
            return Scripts;
        }
    }

    public class MockRole {
        public string Name { get; set; }
        public bool IsFixedRole { get; set; }
        public string[] Members { get; set; }
        public string[] RoleScripts { get; set; }

        public string[] EnumMembers() {
            return Members ?? Array.Empty<string>();
        }

        public string[] Script(object scriptingOptions) {
            return RoleScripts;
        }
    }

    public class MockCredential {
        public string Identity { get; set; }
        public string Name { get; set; }
    }

    public class MockServerRole {
        public string Name { get; set; }
        public string[] Members { get; set; }

        public string[] EnumMemberNames() {
            return Members ?? Array.Empty<string>();
        }

        public string[] EnumServerRoleMembers() {
            return Members ?? Array.Empty<string>();
        }
    }

    public class MockJob {
        public string OwnerLoginName { get; set; }
    }

    public class MockJobServer {
        public List<MockJob> Jobs { get; set; }

        public MockJobServer() {
            Jobs = new List<MockJob>();
        }
    }

    public class MockLogin {
        public string Name { get; set; }
        public string DefaultDatabase { get; set; }
        public string Language { get; set; }
        public bool PasswordPolicyEnforced { get; set; }
        public bool PasswordExpirationEnabled { get; set; }
        public string LoginType { get; set; }
        public bool IsDisabled { get; set; }
        public bool DenyWindowsLogin { get; set; }
        public MockMapping[] DatabaseMappings { get; set; }

        public MockMapping[] EnumDatabaseMappings() {
            return DatabaseMappings ?? Array.Empty<MockMapping>();
        }
    }

    public class MockDatabase {
        public string Name { get; set; }
        public bool IsAccessible { get; set; }
        public string CompatibilityLevel { get; set; }
        public MockCollection<MockRole> Roles { get; set; }
        public MockCollection<MockUser> Users { get; set; }
        public MockMapping[] LoginMappings { get; set; }

        public MockDatabase() {
            Roles = new MockCollection<MockRole>();
            Users = new MockCollection<MockUser>();
        }

        public MockMapping[] EnumLoginMappings() {
            return LoginMappings ?? Array.Empty<MockMapping>();
        }

        public object[] EnumDatabasePermissions(string userName) {
            return Array.Empty<object>();
        }
    }

    public class MockServer {
        public string Name { get; set; }
        public int VersionMajor { get; set; }
        public List<MockLogin> Logins { get; set; }
        public List<MockServerRole> Roles { get; set; }
        public MockJobServer JobServer { get; set; }
        public List<MockCredential> Credentials { get; set; }
        public MockCollection<MockDatabase> Databases { get; set; }

        public MockServer() {
            Logins = new List<MockLogin>();
            Roles = new List<MockServerRole>();
            JobServer = new MockJobServer();
            Credentials = new List<MockCredential>();
            Databases = new MockCollection<MockDatabase>();
        }

        public object[] EnumServerPermissions(string userName) {
            return Array.Empty<object>();
        }
    }
}
"@
            }
        }

        It "Should script role permissions before role membership for non-ObjectLevel export" {
            InModuleScope dbatools {
                function Write-Message { }
                function Test-ExportDirectory { }
                function Test-FunctionInterrupt { $false }
                function Export-DbaDbRole {
                    @(
                        "CREATE ROLE [app_role]",
                        "GRANT SELECT ON SCHEMA::[dbo] TO [app_role]"
                    )
                }
                function Export-DbaUser {
                    @(
                        "CREATE ROLE [app_role]",
                        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'app_user') CREATE USER [app_user] FOR LOGIN [CONTOSO\app_login]",
                        "ALTER ROLE [app_role] ADD MEMBER [app_user]"
                    )
                }
                function Connect-DbaInstance {
                    $mapping = New-Object ExportDbaLoginRoleTest.MockMapping
                    $mapping.DBName = "db1"
                    $mapping.UserName = "app_user"
                    $mapping.LoginName = "CONTOSO\app_login"

                    $user = New-Object ExportDbaLoginRoleTest.MockUser
                    $user.Name = "app_user"
                    $user.Scripts = @(
                        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'app_user') CREATE USER [app_user] FOR LOGIN [CONTOSO\app_login]"
                    )

                    $role = New-Object ExportDbaLoginRoleTest.MockRole
                    $role.Name = "app_role"
                    $role.IsFixedRole = $false
                    $role.Members = @("app_user")
                    $role.RoleScripts = @("CREATE ROLE [app_role]")

                    $database = New-Object ExportDbaLoginRoleTest.MockDatabase
                    $database.Name = "db1"
                    $database.IsAccessible = $true
                    $database.CompatibilityLevel = "Version160"
                    $database.LoginMappings = @($mapping)
                    $database.Users.Add("app_user", $user)
                    $database.Roles.Add("app_role", $role)

                    $login = New-Object ExportDbaLoginRoleTest.MockLogin
                    $login.Name = "CONTOSO\app_login"
                    $login.DefaultDatabase = "master"
                    $login.Language = "us_english"
                    $login.PasswordPolicyEnforced = $true
                    $login.PasswordExpirationEnabled = $true
                    $login.LoginType = "WindowsUser"
                    $login.IsDisabled = $false
                    $login.DenyWindowsLogin = $false
                    $login.DatabaseMappings = @($mapping)

                    $server = New-Object ExportDbaLoginRoleTest.MockServer
                    $server.Name = "mockserver"
                    $server.VersionMajor = 16
                    $server.Logins.Add($login)
                    $server.Databases.Add("db1", $database)

                    $server
                }

                $results = Export-DbaLogin -SqlInstance "mockserver" -Login "CONTOSO\app_login" -Database "db1" -IncludeRolePermissions -Passthru

                $createRoleIndex = $results.IndexOf("CREATE ROLE [app_role]")
                $grantIndex = $results.IndexOf("GRANT SELECT ON SCHEMA::[dbo] TO [app_role]")
                $membershipIndex = $results.IndexOf("ALTER ROLE [app_role] ADD MEMBER [app_user]")

                $createRoleIndex | Should -BeGreaterThan -1
                $grantIndex | Should -BeGreaterThan -1
                $membershipIndex | Should -BeGreaterThan -1
                $createRoleIndex | Should -BeLessThan $membershipIndex
                $grantIndex | Should -BeLessThan $membershipIndex
            }
        }

        It "Should not duplicate role creation in ObjectLevel export" {
            InModuleScope dbatools {
                function Write-Message { }
                function Test-ExportDirectory { }
                function Test-FunctionInterrupt { $false }
                $script:exportDbaDbRoleCalls = 0
                $script:exportDbaUserCalls = 0
                function Export-DbaDbRole {
                    $script:exportDbaDbRoleCalls++
                    @(
                        "CREATE ROLE [app_role]",
                        "GRANT SELECT ON SCHEMA::[dbo] TO [app_role]"
                    )
                }
                function Export-DbaUser {
                    $script:exportDbaUserCalls++
                    @(
                        "CREATE ROLE [app_role]",
                        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'app_user') CREATE USER [app_user] FOR LOGIN [CONTOSO\app_login]",
                        "ALTER ROLE [app_role] ADD MEMBER [app_user]"
                    )
                }
                function Connect-DbaInstance {
                    $mapping = New-Object ExportDbaLoginRoleTest.MockMapping
                    $mapping.DBName = "db1"
                    $mapping.UserName = "app_user"
                    $mapping.LoginName = "CONTOSO\app_login"

                    $user = New-Object ExportDbaLoginRoleTest.MockUser
                    $user.Name = "app_user"
                    $user.Scripts = @(
                        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'app_user') CREATE USER [app_user] FOR LOGIN [CONTOSO\app_login]"
                    )

                    $role = New-Object ExportDbaLoginRoleTest.MockRole
                    $role.Name = "app_role"
                    $role.IsFixedRole = $false
                    $role.Members = @("app_user")
                    $role.RoleScripts = @("CREATE ROLE [app_role]")

                    $database = New-Object ExportDbaLoginRoleTest.MockDatabase
                    $database.Name = "db1"
                    $database.IsAccessible = $true
                    $database.CompatibilityLevel = "Version160"
                    $database.LoginMappings = @($mapping)
                    $database.Users.Add("app_user", $user)
                    $database.Roles.Add("app_role", $role)

                    $login = New-Object ExportDbaLoginRoleTest.MockLogin
                    $login.Name = "CONTOSO\app_login"
                    $login.DefaultDatabase = "master"
                    $login.Language = "us_english"
                    $login.PasswordPolicyEnforced = $true
                    $login.PasswordExpirationEnabled = $true
                    $login.LoginType = "WindowsUser"
                    $login.IsDisabled = $false
                    $login.DenyWindowsLogin = $false
                    $login.DatabaseMappings = @($mapping)

                    $server = New-Object ExportDbaLoginRoleTest.MockServer
                    $server.Name = "mockserver"
                    $server.VersionMajor = 16
                    $server.Logins.Add($login)
                    $server.Databases.Add("db1", $database)

                    $server
                }

                $results = Export-DbaLogin -SqlInstance "mockserver" -Login "CONTOSO\app_login" -Database "db1" -ObjectLevel -IncludeRolePermissions -Passthru
                $createRoleMatches = [regex]::Matches($results, [regex]::Escape("CREATE ROLE [app_role]"))
                $grantIndex = $results.IndexOf("GRANT SELECT ON SCHEMA::[dbo] TO [app_role]")
                $membershipIndex = $results.IndexOf("ALTER ROLE [app_role] ADD MEMBER [app_user]")

                $createRoleMatches.Count | Should -Be 1
                $grantIndex | Should -BeGreaterThan -1
                $membershipIndex | Should -BeGreaterThan -1
                $script:exportDbaUserCalls | Should -Be 1
                $script:exportDbaDbRoleCalls | Should -Be 1
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $DefaultExportPath = Get-DbatoolsConfigValue -FullName path.dbatoolsexport
        $AltExportPath = "$env:USERPROFILE\Documents"
        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbalogin1$random"
        $login1 = "dbatoolsci_exportdbalogin_login1$random"
        $user1 = "dbatoolsci_exportdbalogin_user1$random"

        $dbname2 = "dbatoolsci_exportdbalogin2$random"
        $login2 = "dbatoolsci_exportdbalogin_login2$random"
        $user2 = "dbatoolsci_exportdbalogin_user2$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $db1 = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $db1.Query("CREATE USER [$user1] FOR LOGIN [$login1]")

        $db2 = New-DbaDatabase -SqlInstance $server -Name $dbname2
        $null = $server.Query("CREATE LOGIN [$login2] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("ALTER LOGIN [$login2] DISABLE")
        $null = $server.Query("DENY CONNECT SQL TO [$login2]")

        if ($server.VersionMajor -lt 11) {
            $null = $server.Query("EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$login2'")
        } else {
            $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$login2]")
        }
        $db2.Query("CREATE USER [$user2] FOR LOGIN [$login2]")
        $db2.Query("GRANT SELECT ON sys.tables TO [$user2] WITH GRANT OPTION")

        # login and user that have the same name but aren't linked
        $login3 = "dbatoolsci_exportdbalogin_login3$random"
        $server.Query("CREATE LOGIN [$login3] WITH PASSWORD = 'GoodPass1234!'")
        $db1.Query("CREATE USER [$login3] WITHOUT LOGIN")

        # login with a custom role that has granted permissions (for IncludeRolePermissions tests)
        $login4 = "dbatoolsci_exportdbalogin_login4$random"
        $user4 = "dbatoolsci_exportdbalogin_user4$random"
        $role4 = "dbatoolsci_exportdbalogin_role4$random"
        $null = $server.Query("CREATE LOGIN [$login4] WITH PASSWORD = 'GoodPass1234!'")
        $db1.Query("CREATE USER [$user4] FOR LOGIN [$login4]")
        $db1.Query("CREATE ROLE [$role4]")
        $db1.Query("GRANT SELECT ON SCHEMA::dbo TO [$role4]")
        $db1.Query("GRANT EXECUTE ON SCHEMA::dbo TO [$role4]")
        if ($server.VersionMajor -lt 11) {
            $db1.Query("EXEC sp_addrolemember @rolename = N'$role4', @membername = N'$user4'")
        } else {
            $db1.Query("ALTER ROLE [$role4] ADD MEMBER [$user4]")
        }
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1
        Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname2
        Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2
        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedCredential = Get-ChildItem $DefaultExportPath, $AltExportPath | Where-Object { $_.Name -match "$timenow\d{4}-login.sql|Dbatoolsci_login_CustomFile.sql" }
        if ($ExportedCredential) {
            $null = Remove-Item -Path $($ExportedCredential.FullName)
        }

        Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login3
        Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login4
    }

    Context "Executes with Exclude Parameters" {
        It "Should exclude databases when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Match '\nGo\r'
        }
        It "Should exclude Jobs when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeJobs -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Not -Match 'Job'
        }
        It "Should exclude Go when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -BatchSeparator '' -ObjectLevel -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Not -Match 'GO'
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$dbname2\]"
        }
        It "Should exclude a specific login" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeLogin $login1 -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Not -Match "$login1"
        }
        It "Should exclude passwords" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeLogin $login1 -WarningAction SilentlyContinue -ExcludePassword
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Not -Match '(?<=PASSWORD =\s0x)(\w+)'
        }
    }
    Context "Executes for various users, databases, and environments" {
        It "Should Export a specific user" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login1 -Database $dbname1 -DefaultDatabase master -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should -Not -Match "$login2|$dbname2"
            $results | Should -Match "$login1|$dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$user1')"))
        }
        It "Should Export with object level permissions" {
            $results = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2 -ObjectLevel -PassThru -WarningAction SilentlyContinue
            $results | Should -Not -Match "$login1|$dbname1"
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$dbname2\]"
        }
        It "Should Export for all SQL Server versions" {
            foreach ($version in $((Get-Command $CommandName).Parameters.DestinationVersion.attributes.validvalues)) {
                $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $login2 -Database $dbname2 -DestinationVersion $version -WarningAction SilentlyContinue
                $results = Get-Content -Path $file -Raw
                $allfiles += $file.FullName
                $results | Should -Match "$login2|$dbname2"
                $results | Should -Not -Match "$login1|$dbname1"
            }
        }
        It "Should Export only logins from the db that is piped in" {
            $file = $db1 | Export-DbaLogin
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match "$login2|$dbname2|$login3"
            $results | Should -Match "$login1|$dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$user1')"))
        }
    }
    Context "Executes with IncludeRolePermissions" {
        It "Should include role permissions in non-ObjectLevel export" {
            $results = Export-DbaLogin -SqlInstance $server -Login $login4 -Database $dbname1 -IncludeRolePermissions -Passthru -WarningAction SilentlyContinue
            $createRolePattern = [regex]::Escape("CREATE ROLE [$role4]")
            if ($server.VersionMajor -lt 11) {
                $membershipPattern = [regex]::Escape("@rolename=N'$role4', @membername=N'$user4'")
            } else {
                $membershipPattern = [regex]::Escape("ALTER ROLE [$role4] ADD MEMBER [$user4]")
            }
            $createRoleMatches = [regex]::Matches($results, $createRolePattern)
            $membershipMatch = [regex]::Match($results, $membershipPattern)

            $results | Should -Match "GRANT SELECT ON SCHEMA::\[dbo\]"
            $results | Should -Match "GRANT EXECUTE ON SCHEMA::\[dbo\]"
            $results | Should -Match ([regex]::Escape("[$role4]"))
            $createRoleMatches.Count | Should -Be 1
            $membershipMatch.Success | Should -BeTrue
            $createRoleMatches[0].Index | Should -BeLessThan $membershipMatch.Index
        }
        It "Should include role permissions in ObjectLevel export" {
            $results = Export-DbaLogin -SqlInstance $server -Login $login4 -Database $dbname1 -ObjectLevel -IncludeRolePermissions -Passthru -WarningAction SilentlyContinue
            $createRolePattern = [regex]::Escape("CREATE ROLE [$role4]")
            if ($server.VersionMajor -lt 11) {
                $membershipPattern = [regex]::Escape("@rolename=N'$role4', @membername=N'$user4'")
            } else {
                $membershipPattern = [regex]::Escape("ALTER ROLE [$role4] ADD MEMBER [$user4]")
            }
            $createRoleMatches = [regex]::Matches($results, $createRolePattern)
            $membershipMatch = [regex]::Match($results, $membershipPattern)

            $results | Should -Match "GRANT SELECT ON SCHEMA::\[dbo\]"
            $results | Should -Match "GRANT EXECUTE ON SCHEMA::\[dbo\]"
            $results | Should -Match ([regex]::Escape("[$role4]"))
            $createRoleMatches.Count | Should -Be 1
            $membershipMatch.Success | Should -BeTrue
            $createRoleMatches[0].Index | Should -BeLessThan $membershipMatch.Index
        }
        It "Should not include role permissions without the switch" {
            $results = Export-DbaLogin -SqlInstance $server -Login $login4 -Database $dbname1 -Passthru -WarningAction SilentlyContinue
            $results | Should -Not -Match "GRANT SELECT ON SCHEMA::\[dbo\]"
        }
    }
    Context "Exports file to random and specified paths" {
        It "Should export file to the configured path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should -Be $DefaultExportPath
        }
        It "Should export file to custom folder path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Path $AltExportPath -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should -Be $AltExportPath
        }
        It "Should export file to custom file path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.Name
            $allfiles += $file.FullName
            $results | Should -Be "Dbatoolsci_login_CustomFile.sql"
        }
        It "Should export file to custom file path and Append" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -Append -ExcludeDatabase -WarningAction SilentlyContinue
            $allfiles += $file.FullName
            $file.CreationTimeUtc.Ticks | Should -BeLessThan $file.LastWriteTimeUtc.Ticks
        }
        It "Should not export file to custom file path with NoClobber" {
            { Export-DbaLogin -SqlInstance $TestConfig.InstanceSingle -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -NoClobber -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}