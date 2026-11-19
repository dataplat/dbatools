#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing.
# NativeChecklist: azure-sqldb N/A -- the command expands Windows (Active Directory Domain Services) group logins, which Azure SQL Database does not have: it authenticates SQL logins and Microsoft Entra principals only, and CREATE LOGIN ... FROM WINDOWS is not supported there (https://learn.microsoft.com/sql/t-sql/statements/create-login-transact-sql, https://learn.microsoft.com/azure/azure-sql/database/logins-create-manage). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

BeforeAll {
    # The direct members of a domain group that are not groups, as DOMAIN\sAMAccountName, read independently of the command.
    function Get-NativeGroupMemberLogin {
        param([string]$Group)
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext("Domain", $Group.Split("\")[0])
        $principal = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($context, $Group)
        foreach ($member in $principal.Members) {
            [PSCustomObject]@{
                Login   = $member.Context.Name + "\" + $member.SamAccountName
                IsGroup = $member.StructuralObjectClass -eq "group"
            }
        }
    }

    # Adds a login for a domain group unless the instance has one; returns whether this test created it.
    function Add-NativeGroupLogin {
        param($Server, [string]$Group)
        $literal = $Group.Replace("'", "''")
        $quoted = "[" + $Group.Replace("]", "]]") + "]"
        $created = $Server.ConnectionContext.ExecuteScalar("IF SUSER_ID(N'$literal') IS NULL BEGIN CREATE LOGIN $quoted FROM WINDOWS; SELECT 1; END ELSE SELECT 0;")
        $Server.Logins.Refresh()
        [bool]$created
    }

    function Remove-NativeGroupLogin {
        param($Server, [string]$Group)
        $literal = $Group.Replace("'", "''")
        $quoted = "[" + $Group.Replace("]", "]]") + "]"
        $null = $Server.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$literal') IS NOT NULL DROP LOGIN $quoted;")
    }
}

Describe "Native Find-DbaLoginInGroup" -Tag IntegrationTests {
    BeforeAll {
        $groupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $groupBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $groupDomain = $env:USERDOMAIN
        $groupFlat = "$groupDomain\Domain Admins"
        # A built-in domain-local group whose default members include other groups (Domain Admins, Enterprise Admins,
        # Schema Admins, Domain Controllers and more) and the krbtgt user.
        $groupNested = "$groupDomain\Denied RODC Password Replication Group"
        $groupCreated = @{}
        foreach ($groupName in $groupFlat, $groupNested) {
            $groupCreated[$groupName] = Add-NativeGroupLogin -Server $groupServer -Group $groupName
        }
        $groupFlatMembers = @(Get-NativeGroupMemberLogin -Group $groupFlat)
        $groupNestedMembers = @(Get-NativeGroupMemberLogin -Group $groupNested)
        $groupDefaults = "SqlInstance,Login,DisplayName,MemberOf,ParentADGroupLogin"
        $groupFlatUser = @($groupFlatMembers | Where-Object { -not $PSItem.IsGroup })[0].Login
    }

    AfterAll {
        foreach ($groupName in $groupFlat, $groupNested) {
            if ($groupCreated[$groupName]) {
                Remove-NativeGroupLogin -Server $groupServer -Group $groupName
            }
        }
    }

    It "expands a Windows group login into its members with the pinned shape" {
        $groupRows = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue)
        $groupFlatRows = @($groupRows | Where-Object ParentADGroupLogin -eq $groupFlat)
        $groupExpected = @($groupFlatMembers | Where-Object { -not $PSItem.IsGroup } | ForEach-Object Login | Sort-Object -Unique)
        $groupExpected.Count | Should -BeGreaterThan 0
        @($groupFlatRows | Where-Object MemberOf -eq $groupFlat | ForEach-Object Login | Sort-Object -Unique) | Should -Be $groupExpected
        $groupFlatRows[0].SqlInstance | Should -Be $groupServer.Name
        $groupFlatRows[0].InstanceName | Should -Be $groupServer.ServiceName
        ($groupFlatRows[0].PSObject.Properties.Name -join ",") | Should -BeExactly "SqlInstance,InstanceName,ComputerName,Login,DisplayName,MemberOf,ParentADGroupLogin"
        ($groupFlatRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $groupDefaults
    }

    It "expands nested groups recursively and emits their members before the group's own" {
        @($groupNestedMembers | Where-Object IsGroup).Count | Should -BeGreaterThan 0
        $groupRows = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue | Where-Object ParentADGroupLogin -eq $groupNested)
        $groupOwn = @($groupNestedMembers | Where-Object { -not $PSItem.IsGroup } | ForEach-Object Login | Sort-Object -Unique)
        $groupOwn.Count | Should -BeGreaterThan 0
        @($groupRows | Where-Object MemberOf -eq $groupNested | ForEach-Object Login | Sort-Object -Unique) | Should -Be $groupOwn
        $groupInner = @($groupRows | Where-Object MemberOf -ne $groupNested)
        $groupInner.Count | Should -BeGreaterThan 0
        $groupLastInner = [array]::LastIndexOf([object[]]$groupRows, $groupInner[-1])
        $groupFirstOwn = [array]::IndexOf([object[]]$groupRows, @($groupRows | Where-Object MemberOf -eq $groupNested)[0])
        $groupLastInner | Should -BeLessThan $groupFirstOwn
    }

    It "returns only the logins named by -Login" {
        $groupWanted = @($groupFlatMembers | Where-Object { -not $PSItem.IsGroup })[0].Login
        $groupRows = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login $groupWanted.ToUpperInvariant() -WarningAction SilentlyContinue)
        $groupRows.Count | Should -BeGreaterThan 0
        @($groupRows | Where-Object Login -ne $groupWanted).Count | Should -Be 0
        @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login "nodomain\nobody_$([Guid]::NewGuid().ToString('N'))" -WarningAction SilentlyContinue).Count | Should -Be 0
    }

    It "searches every piped instance" -Tag NativeChecklist:pipeline-multiple {
        $groupSingle = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login $groupFlatUser -WarningAction SilentlyContinue)
        $groupPiped = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Find-DbaLoginInGroup -Login $groupFlatUser -WarningAction SilentlyContinue)
        $groupSingle.Count | Should -BeGreaterThan 0
        $groupPiped.Count | Should -Be (2 * $groupSingle.Count)
    }

    It "warns for a failed instance and continues with the next one" -Tag NativeChecklist:multi-instance-failure {
        $groupWarnings = @()
        $groupRows = @(Find-DbaLoginInGroup -SqlInstance $groupBadInstance, $TestConfig.InstanceSingle -WarningVariable groupWarnings -WarningAction SilentlyContinue)
        ($groupWarnings -join " ") | Should -BeLike "*Failure*"
        @($groupRows | Where-Object ParentADGroupLogin -eq $groupFlat).Count | Should -BeGreaterThan 0
    }

    It "keeps earlier output before -EnableException stops at a failed instance" -Tag NativeChecklist:enable-exception {
        $groupStreamed = New-Object "System.Collections.Generic.List[object]"
        $groupCaught = $null
        try {
            Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle, $groupBadInstance -EnableException |
                ForEach-Object { $groupStreamed.Add($PSItem) }
        } catch {
            $groupCaught = $PSItem
        }
        $groupStreamed.Count | Should -BeGreaterThan 0
        $groupCaught | Should -Not -BeNullOrEmpty
        $groupCaught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "warns and goes on when -EnableException is false" -Tag NativeChecklist:switch-false {
        $groupWarnings = @()
        $groupCaught = $null
        try {
            $groupRows = @(Find-DbaLoginInGroup -SqlInstance $groupBadInstance, $TestConfig.InstanceSingle -EnableException:$false -WarningVariable groupWarnings -WarningAction SilentlyContinue)
        } catch {
            $groupCaught = $PSItem
        }
        $groupCaught | Should -BeNullOrEmpty
        ($groupWarnings -join " ") | Should -BeLike "*Failure*"
        @($groupRows | Where-Object ParentADGroupLogin -eq $groupFlat).Count | Should -BeGreaterThan 0
    }

    It "treats an empty -Login as no filter" {
        $groupAll = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue)
        $groupEmpty = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login "" -WarningAction SilentlyContinue)
        $groupAll.Count | Should -BeGreaterThan 0
        $groupEmpty.Count | Should -Be $groupAll.Count
    }

    Context "A group login that names no domain" {
        BeforeAll {
            # BUILTIN is no domain, so the PrincipalContext constructor fails for this login.
            $groupBuiltin = "BUILTIN\Users"
            $groupBuiltinCreated = Add-NativeGroupLogin -Server $groupServer -Group $groupBuiltin
        }

        AfterAll {
            if ($groupBuiltinCreated) {
                Remove-NativeGroupLogin -Server $groupServer -Group $groupBuiltin
            }
        }

        It "warns as Get-AllLogins and goes on to the other groups" {
            $groupWarnings = @()
            $groupRows = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -WarningVariable groupWarnings -WarningAction SilentlyContinue)
            ($groupWarnings -join " ") | Should -BeLike "*Get-AllLogins*Failed to connect to Group: .*"
            @($groupRows | Where-Object ParentADGroupLogin -eq $groupFlat).Count | Should -BeGreaterThan 0
            @($groupRows | Where-Object ParentADGroupLogin -eq $groupBuiltin).Count | Should -Be 0
        }

        It "throws the Get-AllLogins failure under -EnableException" {
            $groupCaught = $null
            try {
                $null = Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -EnableException
            } catch {
                $groupCaught = $PSItem
            }
            $groupCaught | Should -Not -BeNullOrEmpty
            $groupCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-AllLogins*"
            $groupCaught.CategoryInfo.Category | Should -Be "InvalidOperation"
            $groupCaught.Exception.InnerException.GetType().Name | Should -Be "MethodInvocationException"
            $groupCaught.Exception.InnerException.Message | Should -BeLike 'Exception calling ".ctor" with "2" argument(s):*'
        }
    }
}

Describe "Native Find-DbaLoginInGroup over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $loginCaught = $null
            try {
                $null = Find-DbaLoginInGroup -SqlInstance $loginInstance -SqlCredential $loginCred -WarningVariable loginWarnings -WarningAction SilentlyContinue
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -BeNullOrEmpty
            @($loginWarnings | Where-Object { "$PSItem" -like "*Failure*" }).Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $loginRows = @(Find-DbaLoginInGroup -SqlInstance $loginInstance -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $loginRows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $loginCaught = $null
            try {
                $null = Find-DbaLoginInGroup -SqlInstance $loginInstance -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Find-DbaLoginInGroup refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Find-DbaLoginInGroup @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Find-DbaLoginInGroup -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
    }
}
