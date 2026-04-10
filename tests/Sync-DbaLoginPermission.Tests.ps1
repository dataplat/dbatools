#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Sync-DbaLoginPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "SMO enumeration handling" {
            BeforeAll {
                if (-not ("SyncDbaLoginPermissionReaderTest.MockServer" -as [type])) {
                    Add-Type -TypeDefinition @"
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;

namespace SyncDbaLoginPermissionReaderTest {
    public class GuardState {
        public bool Active { get; set; }
    }

    public class GuardedEnumerator : IEnumerator {
        private readonly object[] items;
        private readonly GuardState guard;
        private int index = -1;

        public GuardedEnumerator(object[] items, GuardState guard) {
            this.items = items;
            this.guard = guard;
        }

        public object Current {
            get { return items[index]; }
        }

        public bool MoveNext() {
            int next = index + 1;

            if (guard != null && next == 0) {
                guard.Active = true;
            }

            if (next >= items.Length) {
                if (guard != null) {
                    guard.Active = false;
                }
                return false;
            }

            index = next;
            return true;
        }

        public void Reset() {
            index = -1;
            if (guard != null) {
                guard.Active = false;
            }
        }
    }

    public class NamedCollection<T> : IEnumerable {
        protected readonly Dictionary<string, T> items = new Dictionary<string, T>(StringComparer.OrdinalIgnoreCase);

        public void Add(string name, T item) {
            items[name] = item;
        }

        public T this[string name] {
            get {
                T value;
                items.TryGetValue(name, out value);
                return value;
            }
        }

        public object[] Values() {
            return items.Values.Cast<object>().ToArray();
        }

        public IEnumerator GetEnumerator() {
            return items.Values.GetEnumerator();
        }
    }

    public class GuardedNamedCollection<T> : NamedCollection<T> {
        public GuardState Guard { get; set; }

        public new IEnumerator GetEnumerator() {
            return new GuardedEnumerator(Values(), Guard);
        }
    }

    public class GuardedEnumerable : IEnumerable {
        private readonly object[] items;
        private readonly GuardState guard;

        public GuardedEnumerable(GuardState guard, object[] items) {
            this.guard = guard;
            this.items = items;
        }

        public IEnumerator GetEnumerator() {
            return new GuardedEnumerator(items, guard);
        }
    }

    public class MockMapping {
        public string DbName { get; set; }
        public string Username { get; set; }
        public string LoginName { get; set; }
    }

    public class MockUser {
        public string Name { get; set; }

        public string[] Script() {
            return Array.Empty<string>();
        }

        public void Drop() {
        }
    }

    public class MockServerRole {
        public string Name { get; set; }
        public string[] Members { get; set; }
        public GuardState PrimaryConflictGuard { get; set; }
        public GuardState SecondaryConflictGuard { get; set; }

        private void ThrowIfReaderActive() {
            if ((PrimaryConflictGuard != null && PrimaryConflictGuard.Active) ||
                (SecondaryConflictGuard != null && SecondaryConflictGuard.Active)) {
                throw new InvalidOperationException("Open reader conflict");
            }
        }

        public string[] EnumMemberNames() {
            ThrowIfReaderActive();
            return Members ?? Array.Empty<string>();
        }

        public string[] EnumServerRoleMembers() {
            return EnumMemberNames();
        }

        public void AddMember(string name) {
        }

        public void DropMember(string name) {
        }
    }

    public class MockDatabaseRole {
        public string Name { get; set; }
        public string[] Members { get; set; }
        public GuardState PrimaryConflictGuard { get; set; }
        public GuardState SecondaryConflictGuard { get; set; }

        private void ThrowIfReaderActive() {
            if ((PrimaryConflictGuard != null && PrimaryConflictGuard.Active) ||
                (SecondaryConflictGuard != null && SecondaryConflictGuard.Active)) {
                throw new InvalidOperationException("Open reader conflict");
            }
        }

        public string[] EnumMembers() {
            ThrowIfReaderActive();
            return Members ?? Array.Empty<string>();
        }

        public void AddMember(string name) {
        }

        public void DropMember(string name) {
        }
    }

    public class MockDatabase {
        public string Name { get; set; }
        public bool IsAccessible { get; set; }
        public bool IsUpdateable { get; set; }
        public string Owner { get; set; }
        public string CompatibilityLevel { get; set; }
        public GuardState ConflictGuard { get; set; }
        public GuardedNamedCollection<MockDatabaseRole> Roles { get; set; } = new GuardedNamedCollection<MockDatabaseRole>();
        public NamedCollection<MockUser> Users { get; set; } = new NamedCollection<MockUser>();

        private void ThrowIfReaderActive() {
            if (ConflictGuard != null && ConflictGuard.Active) {
                throw new InvalidOperationException("Open reader conflict");
            }
        }

        public object[] EnumDatabasePermissions(string userName) {
            ThrowIfReaderActive();
            return Array.Empty<object>();
        }

        public void Alter() {
        }

        public void ExecuteNonQuery(string sql) {
        }
    }

    public class MockCredential {
        public string Identity { get; set; }
        public string Name { get; set; }
    }

    public class MockJobServer {
        public object[] Jobs { get; set; } = Array.Empty<object>();
    }

    public class MockLogin {
        public string Name { get; set; }
        public bool IsDisabled { get; set; }
        public GuardState EnumerationGuard { get; set; }
        public object[] DatabaseMappings { get; set; }

        public IEnumerable EnumDatabaseMappings() {
            return new GuardedEnumerable(EnumerationGuard, DatabaseMappings ?? Array.Empty<object>());
        }

        public void Enable() {
            IsDisabled = false;
        }

        public void Disable() {
            IsDisabled = true;
        }

        public void Alter() {
        }
    }

    public class MockServer {
        public string DomainInstanceName { get; set; }
        public int VersionMajor { get; set; }
        public GuardedNamedCollection<MockServerRole> Roles { get; set; } = new GuardedNamedCollection<MockServerRole>();
        public MockJobServer JobServer { get; set; } = new MockJobServer();
        public NamedCollection<MockCredential> Credentials { get; set; } = new NamedCollection<MockCredential>();
        public NamedCollection<MockDatabase> Databases { get; set; } = new NamedCollection<MockDatabase>();

        public object[] EnumServerPermissions(string userName) {
            return Array.Empty<object>();
        }
    }
}
"@
                }
            }

            BeforeEach {
                function Get-SaLoginName {
                    param($SqlInstance)
                    "sa"
                }
                function Write-Message { }
                function Stop-Function {
                    param(
                        [string]$Message,
                        $Target,
                        $ErrorRecord,
                        [switch]$Continue
                    )

                    if ($null -ne $ErrorRecord) {
                        throw $ErrorRecord.Exception
                    }

                    throw $Message
                }
            }

            It "Should materialize SMO enumerations before nested permission lookups" {
                $sourceServerRoleGuard = New-Object SyncDbaLoginPermissionReaderTest.GuardState
                $sourceMappingGuard = New-Object SyncDbaLoginPermissionReaderTest.GuardState
                $sourceDatabaseRoleGuard = New-Object SyncDbaLoginPermissionReaderTest.GuardState
                $destMappingGuard = New-Object SyncDbaLoginPermissionReaderTest.GuardState

                $sourceServer = New-Object SyncDbaLoginPermissionReaderTest.MockServer
                $sourceServer.DomainInstanceName = "source"
                $sourceServer.VersionMajor = 9
                $sourceServer.Roles.Guard = $sourceServerRoleGuard

                $destServer = New-Object SyncDbaLoginPermissionReaderTest.MockServer
                $destServer.DomainInstanceName = "destination"
                $destServer.VersionMajor = 9

                $sourceServerRole = New-Object SyncDbaLoginPermissionReaderTest.MockServerRole
                $sourceServerRole.Name = "sysadmin"
                $sourceServerRole.Members = @()
                $sourceServerRole.PrimaryConflictGuard = $sourceServerRoleGuard
                $sourceServer.Roles.Add("sysadmin", $sourceServerRole)

                $destServerRole = New-Object SyncDbaLoginPermissionReaderTest.MockServerRole
                $destServerRole.Name = "sysadmin"
                $destServerRole.Members = @()
                $destServer.Roles.Add("sysadmin", $destServerRole)

                $sourceLogin = New-Object SyncDbaLoginPermissionReaderTest.MockLogin
                $sourceLogin.Name = "login1"
                $sourceLogin.EnumerationGuard = $sourceMappingGuard

                $destLogin = New-Object SyncDbaLoginPermissionReaderTest.MockLogin
                $destLogin.Name = "login1"
                $destLogin.EnumerationGuard = $destMappingGuard

                $sourceMapping = New-Object SyncDbaLoginPermissionReaderTest.MockMapping
                $sourceMapping.DbName = "db1"
                $sourceMapping.Username = "login1"
                $sourceMapping.LoginName = "login1"
                $sourceLogin.DatabaseMappings = @($sourceMapping)

                $destMapping = New-Object SyncDbaLoginPermissionReaderTest.MockMapping
                $destMapping.DbName = "db1"
                $destMapping.Username = "login1"
                $destMapping.LoginName = "login1"
                $destLogin.DatabaseMappings = @($destMapping)

                $sourceDb = New-Object SyncDbaLoginPermissionReaderTest.MockDatabase
                $sourceDb.Name = "db1"
                $sourceDb.IsAccessible = $true
                $sourceDb.IsUpdateable = $true
                $sourceDb.Owner = "dbo"
                $sourceDb.ConflictGuard = $sourceMappingGuard
                $sourceDb.Roles.Guard = $sourceDatabaseRoleGuard

                $destDb = New-Object SyncDbaLoginPermissionReaderTest.MockDatabase
                $destDb.Name = "db1"
                $destDb.IsAccessible = $true
                $destDb.IsUpdateable = $true
                $destDb.Owner = "dbo"
                $destDb.ConflictGuard = $destMappingGuard

                $sourceDbUser = New-Object SyncDbaLoginPermissionReaderTest.MockUser
                $sourceDbUser.Name = "login1"
                $sourceDb.Users.Add("login1", $sourceDbUser)

                $destDbUser = New-Object SyncDbaLoginPermissionReaderTest.MockUser
                $destDbUser.Name = "login1"
                $destDb.Users.Add("login1", $destDbUser)

                $sourceDbRole = New-Object SyncDbaLoginPermissionReaderTest.MockDatabaseRole
                $sourceDbRole.Name = "db_datareader"
                $sourceDbRole.Members = @()
                $sourceDbRole.PrimaryConflictGuard = $sourceMappingGuard
                $sourceDbRole.SecondaryConflictGuard = $sourceDatabaseRoleGuard
                $sourceDb.Roles.Add("db_datareader", $sourceDbRole)

                $destDbRole = New-Object SyncDbaLoginPermissionReaderTest.MockDatabaseRole
                $destDbRole.Name = "db_datareader"
                $destDbRole.Members = @()
                $destDb.Roles.Add("db_datareader", $destDbRole)

                $destLegacyRole = New-Object SyncDbaLoginPermissionReaderTest.MockDatabaseRole
                $destLegacyRole.Name = "legacy_role"
                $destLegacyRole.Members = @()
                $destLegacyRole.PrimaryConflictGuard = $destMappingGuard
                $destDb.Roles.Add("legacy_role", $destLegacyRole)

                $sourceServer.Databases.Add("db1", $sourceDb)
                $destServer.Databases.Add("db1", $destDb)

                {
                    Update-SqlPermission -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin -EnableException
                } | Should -Not -Throw
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $tempguid = [guid]::newguid()
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
GRANT VIEW ANY DEFINITION to [$DBUserName];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $CreateTestUser -Database master

        # This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@
    }
    AfterAll {
        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $DropTestUser -Database master
    }

    Context "Command execution and functionality" {

        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName }
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            # Creates the user on
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $DBUserName -ExcludeLogin 'NotaLogin' -WarningVariable $warn
            $results.Status | Should -Be 'Successful'
            $warn | Should -BeNullOrEmpty
        }

        # The copy failes on Appveyor with: Failed to create or use STIG schema on APPVYR-WIN\sql2017
        It "Should have copied the user permissions of $DBUserName" -Skip:$env:appveyor {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName -and $_.permission -eq 'VIEW ANY DEFINITION' }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }

    Context "Login state synchronization" {
        BeforeAll {
            $tempLoginGuid = [guid]::newguid()
            $stateTestLogin = "dbatoolssci_state_$($tempLoginGuid.guid)"
            $createStateLogin = @"
CREATE LOGIN [$stateTestLogin]
    WITH PASSWORD = '$($tempLoginGuid.guid)';
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $createStateLogin
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $createStateLogin

            # Disable and deny connect on source
            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Query       = "ALTER LOGIN [$stateTestLogin] DISABLE; DENY CONNECT SQL TO [$stateTestLogin];"
            }
            Invoke-DbaQuery @splatDisable
        }
        AfterAll {
            $dropStateLogin = "DROP LOGIN [$stateTestLogin]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $dropStateLogin -Database master
        }

        It "Should sync login disabled state from source to destination" {
            $sourceLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $stateTestLogin
            $sourceLogin.IsDisabled | Should -Be $true

            $destLoginBefore = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginBefore.IsDisabled | Should -Be $false

            $splatSync = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $TestConfig.InstanceMulti2
                Login       = $stateTestLogin
            }
            $results = Sync-DbaLoginPermission @splatSync
            $results.Status | Should -Be "Successful"

            $destLoginAfter = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginAfter.IsDisabled | Should -Be $true
        }
    }
}