#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this read-only command does not support ShouldProcess.

Describe "Get-DbaAgentJobCategory native behavior" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativePrefix = "native_jobcategory_$([Guid]::NewGuid().ToString("N"))"
        $nativeNames = @("${nativePrefix}_a", "${nativePrefix}_b")
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        foreach ($nativeName in $nativeNames) {
            $nativeCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory($nativeServer.JobServer, $nativeName)
            $nativeCategory.CategoryType = [Microsoft.SqlServer.Management.Smo.Agent.CategoryType]::LocalJob
            $nativeCategory.Create()
        }
        $nativeFixtureNames = @("${nativePrefix}_job1", "${nativePrefix}_job2")
        foreach ($nativeFixtureName in $nativeFixtureNames) {
            $nativeFixture = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($nativeServer.JobServer, $nativeFixtureName)
            $nativeFixture.Category = $nativeNames[0]
            $nativeFixture.IsEnabled = $false
            $nativeFixture.Create()
            $nativeFixture.ApplyToTargetServer("(local)")
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeCleanup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeCleanup.JobServer.Jobs.Refresh()
        foreach ($nativeCleanupName in $nativeFixtureNames) {
            $nativeCleanupJob = $nativeCleanup.JobServer.Jobs[$nativeCleanupName]
            if ($null -ne $nativeCleanupJob) { $nativeCleanupJob.Drop() }
        }
        $nativeCleanup.JobServer.JobCategories.Refresh()
        foreach ($nativeCleanupCategoryName in $nativeNames) {
            $nativeCleanupCategory = $nativeCleanup.JobServer.JobCategories[$nativeCleanupCategoryName]
            if ($null -ne $nativeCleanupCategory) { $nativeCleanupCategory.Drop() }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "preserves exact filters, typed categories, usage counts and default display" {
        $splatNativeFilters = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = $nativeNames
            EnableException = $true
        }
        $nativeOutput = @(Get-DbaAgentJobCategory @splatNativeFilters)
        $nativeOutput.Count | Should -Be 2
        $nativePopulated = $nativeOutput | Where-Object Name -EQ $nativeNames[0]
        $nativeEmpty = $nativeOutput | Where-Object Name -EQ $nativeNames[1]
        $nativePopulated | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobCategory
        $nativePopulated.JobCount | Should -Be 2
        $nativeEmpty.JobCount | Should -Be 0
        $nativePopulated.ComputerName | Should -Not -BeNullOrEmpty
        $nativePopulated.InstanceName | Should -Not -BeNullOrEmpty
        $nativePopulated.SqlInstance | Should -Not -BeNullOrEmpty
        ($nativePopulated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,CategoryType,JobCount"
        $splatNativeFilters.Category = @($nativeNames[0].ToUpperInvariant(), $nativeNames[0])
        $nativeFiltered = @(Get-DbaAgentJobCategory @splatNativeFilters)
        $nativeFiltered.Count | Should -Be 1
        $nativeFiltered[0].Name | Should -BeExactly $nativeNames[0]
        $nativeFiltered[0].JobCount | Should -Be 2
        $splatNativeFilters.Category = "${nativePrefix}_*"
        @(Get-DbaAgentJobCategory @splatNativeFilters).Count | Should -Be 0
        $splatNativeFilters.Category = $nativeNames
        $splatNativeFilters.CategoryType = "localjob"
        @(Get-DbaAgentJobCategory @splatNativeFilters).Count | Should -Be 2
        $splatNativeFilters.CategoryType = "MultiServerJob"
        @(Get-DbaAgentJobCategory @splatNativeFilters).Count | Should -Be 0
    }

    It "stops cleanly when the consumer takes only the first category" {
        foreach ($enableErrors in @($false, $true)) {
            $earlyWarnings = @()
            $earlyErrors = @()
            $earlyOutput = @(Get-DbaAgentJobCategory -SqlInstance @($nativeServer, $nativeBadInstance) -Category $nativeNames -EnableException:$enableErrors -WarningAction SilentlyContinue -WarningVariable earlyWarnings -ErrorVariable earlyErrors | Select-Object -First 1)
            $earlyOutput.Count | Should -Be 1
            $earlyOutput[0].Name | Should -BeExactly $nativeNames[0]
            $earlyWarnings.Count | Should -Be 0
            $earlyErrors.Count | Should -Be 0
        }
    }

    It "replaces stale decorations on the same cached SMO category" {
        $splatNativeCachedCategory = @{
            SqlInstance     = $nativeServer
            Category        = $nativeNames[0]
            EnableException = $true
        }
        $nativeCached = Get-DbaAgentJobCategory @splatNativeCachedCategory
        $nativeExpectedInstance = @($nativeCached.ComputerName, $nativeCached.InstanceName, $nativeCached.SqlInstance)
        $nativeCached.ComputerName = "stale"
        $nativeCached.InstanceName = "stale"
        $nativeCached.SqlInstance = "stale"
        $nativeCached.JobCount = -1
        $nativeCached | Add-Member -NotePropertyName NativeCacheMarker -NotePropertyValue "retained"

        $nativeRepeated = Get-DbaAgentJobCategory @splatNativeCachedCategory
        [Object]::ReferenceEquals($nativeCached.PSObject.BaseObject, $nativeRepeated.PSObject.BaseObject) | Should -BeTrue
        $nativeRepeated | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobCategory
        $nativeRepeated.JobCount | Should -Be 2
        $nativeRepeated.NativeCacheMarker | Should -BeExactly "retained"
        $nativeRepeated.ComputerName | Should -BeExactly $nativeExpectedInstance[0]
        $nativeRepeated.InstanceName | Should -BeExactly $nativeExpectedInstance[1]
        $nativeRepeated.SqlInstance | Should -BeExactly $nativeExpectedInstance[2]
        ($nativeRepeated.PSObject.Properties.Name | Where-Object { $PSItem -in @("ComputerName", "InstanceName", "SqlInstance", "JobCount") }) -join "," |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,JobCount"
        ($nativeRepeated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,CategoryType,JobCount"
    }

    It "warns on a failed middle input and continues without duplicating output" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $nativeWarnings = @()
        $splatNativeContinue = @{
            Category        = $nativeNames[0]
            EnableException = $false
            WarningVariable = "nativeWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $nativeContinued = @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle | Get-DbaAgentJobCategory @splatNativeContinue)
        $nativeContinued.Count | Should -Be 2
        $nativeContinued[0].Name | Should -BeExactly $nativeNames[0]
        $nativeContinued[1].Name | Should -BeExactly $nativeNames[0]
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
    }


    It "handles a category read denied after a successful connection" {
        $nativeDeniedName = "${nativePrefix}_denied"
        $nativeDeniedServer = $null
        $nativeUserCreated = $false
        try {
            $nativeServer.Databases["msdb"].ExecuteNonQuery("CREATE USER [$nativeDeniedName] WITHOUT LOGIN; DENY SELECT ON OBJECT::dbo.syscategories TO [$nativeDeniedName];")
            $nativeUserCreated = $true
            $splatDeniedConnection = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = "msdb"
                NonPooledConnection = $true
                ClientName          = $nativeDeniedName
                EnableException     = $true
            }
            $nativeDeniedServer = Connect-DbaInstance @splatDeniedConnection
            $nativeDeniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$nativeDeniedName';") | Out-Null
            $nativeDeniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $nativeDeniedName
            # Prove the middle input connects; its failure must occur during the category read.
            $nativeVerifiedServer = Connect-DbaInstance -SqlInstance $nativeDeniedServer -EnableException
            [Object]::ReferenceEquals($nativeDeniedServer, $nativeVerifiedServer) | Should -BeTrue

            foreach ($categoryFilter in @(@{}, @{ Category = $nativeNames[0] }, @{ CategoryType = 'LocalJob' })) {
                # Pin public/Get-DbaAgentJobCategory.ps1:101-105 always filters outside its try.
                $pinnedReadFault = $null
                try {
                    $jobCategories = $nativeDeniedServer.JobServer.JobCategories |
                        Where-Object {
                            ($_.Name -in $categoryFilter.Category -or !$categoryFilter.Category) -and
                            ($_.CategoryType -in $categoryFilter.CategoryType -or !$categoryFilter.CategoryType)
                        }
                } catch { $pinnedReadFault = $_ }
                $pinnedReadFault | Should -Not -BeNullOrEmpty
                # Whole-function probe: Get-DbaAgentAlertCategory/evidence/errorforms-probe-20261030.txt.
                # Manager 057ab857b1eb: read-only failures may continue with one error
                # and no stale rows; ErrorAction Stop or EnableException terminates.
                # The raw expression supplies exception/message/category/target only.
                $expectedNames = @($nativeServer.JobServer.JobCategories | Where-Object {
                    ($_.Name -in $categoryFilter.Category -or !$categoryFilter.Category) -and
                    ($_.CategoryType -in $categoryFilter.CategoryType -or !$categoryFilter.CategoryType)
                } | ForEach-Object Name)
                $expectedNames.Count | Should -BeGreaterThan 0
                $nativeReadWarnings = @()
                $nativeReadMerged = @($nativeServer, $nativeDeniedServer, $nativeServer |
                    Get-DbaAgentJobCategory @categoryFilter -EnableException:$false -ErrorAction Continue -WarningAction SilentlyContinue -WarningVariable nativeReadWarnings 2>&1)
                $nativeReadMerged.Count | Should -Be (2 * $expectedNames.Count + 1)
                $nativeReadWarnings.Count | Should -Be 0
                for ($index = 0; $index -lt $expectedNames.Count; $index++) {
                    foreach ($position in @($index, ($index + $expectedNames.Count + 1))) {
                        $nativeReadMerged[$position].Name | Should -BeExactly $expectedNames[$index]
                        [Object]::ReferenceEquals($nativeReadMerged[$position].Parent.Parent, $nativeServer) | Should -BeTrue
                    }
                }
                $nativeReadFault = $nativeReadMerged[$expectedNames.Count]
                $nativeReadFault | Should -BeOfType System.Management.Automation.ErrorRecord
                $nativeReadFault.Exception.GetType().FullName | Should -BeExactly $pinnedReadFault.Exception.GetType().FullName
                $nativeReadFault.Exception.Message | Should -BeExactly $pinnedReadFault.Exception.Message
                $nativeReadFault.FullyQualifiedErrorId | Should -BeExactly 'ExceptionInGetEnumerator,Dataplat.Dbatools.Commands.GetDbaAgentJobCategoryCommand'
                $nativeReadFault.CategoryInfo.Category | Should -Be $pinnedReadFault.CategoryInfo.Category
                $nativeReadFault.TargetObject | Should -Be $pinnedReadFault.TargetObject
                $nativeReadFault.InvocationInfo.MyCommand.Name | Should -BeExactly 'Get-DbaAgentJobCategory'

                $hiddenErrors = @()
                $hiddenOutput = @($nativeServer, $nativeDeniedServer, $nativeServer |
                    Get-DbaAgentJobCategory @categoryFilter -EnableException:$false -ErrorAction SilentlyContinue -ErrorVariable hiddenErrors 2>&1)
                $hiddenOutput.Count | Should -Be (2 * $expectedNames.Count)
                @($hiddenOutput | Where-Object Name -EQ $nativeNames[0]).Count | Should -Be 2
                $hiddenErrors.Count | Should -Be 1

                foreach ($terminationMode in @('ErrorAction', 'EnableException')) {
                    $splatReadFailure = $categoryFilter.Clone()
                    $splatReadFailure.EnableException = ($terminationMode -eq 'EnableException')
                    $splatReadFailure.ErrorAction = $(if ($terminationMode -eq 'ErrorAction') { 'Stop' } else { 'Continue' })
                    $nativeReadStreamed = New-Object 'System.Collections.Generic.List[object]'
                    $nativeReadCaught = $null
                    try {
                        $nativeServer, $nativeDeniedServer, $nativeServer |
                            Get-DbaAgentJobCategory @splatReadFailure |
                            ForEach-Object { $nativeReadStreamed.Add($_) }
                    } catch { $nativeReadCaught = $_ }
                    $nativeReadStreamed.Count | Should -Be $expectedNames.Count
                    @($nativeReadStreamed | Where-Object Name -EQ $nativeNames[0]).Count | Should -Be 1
                    $nativeReadCaught | Should -Not -BeNullOrEmpty
                    $nativeReadCaught.FullyQualifiedErrorId | Should -BeExactly $nativeReadFault.FullyQualifiedErrorId
                    $nativeReadCaught.Exception.Message | Should -BeExactly $nativeReadFault.Exception.Message
                    $nativeReadCaught.CategoryInfo.Category | Should -Be $nativeReadFault.CategoryInfo.Category
                    $nativeReadCaught.TargetObject | Should -Be $nativeReadFault.TargetObject
                }
            }
        } finally {
            if ($null -ne $nativeDeniedServer) { $nativeDeniedServer.ConnectionContext.Disconnect() }
            if ($nativeUserCreated) { $nativeServer.Databases["msdb"].ExecuteNonQuery("DROP USER [$nativeDeniedName];") }
        }
    }

    It "streams the first input before EnableException terminates the pipeline" -Tag NativeChecklist:enable-exception {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        $splatNativeThrow = @{
            Category        = $nativeNames[0]
            EnableException = $true
        }
        try {
            $TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle |
                Get-DbaAgentJobCategory @splatNativeThrow |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeStreamed[0].Name | Should -BeExactly $nativeNames[0]
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
    }
}

Describe "Get-DbaAgentJobCategory SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginCategoryName = "native_jobcategory_login_$([guid]::NewGuid().ToString('N'))"
        $loginCategoryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $loginCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory($loginCategoryServer.JobServer, $loginCategoryName)
        $loginCategory.CategoryType = [Microsoft.SqlServer.Management.Smo.Agent.CategoryType]::LocalJob
        $loginCategory.Create()
    }

    AfterAll {
        if ($null -ne $loginCategoryServer) {
            $loginCategoryServer.JobServer.JobCategories.Refresh()
            $loginCategoryCleanup = $loginCategoryServer.JobServer.JobCategories[$loginCategoryName]
            if ($null -ne $loginCategoryCleanup) { $loginCategoryCleanup.Drop() }
        }
    }

    It "returns the requested category with SQL credentials" {
        $splatLoginCategory = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Category = $loginCategoryName
            EnableException = $true
        }
        $loginCategoryOutput = @(Get-DbaAgentJobCategory @splatLoginCategory)
        $loginCategoryOutput.Count | Should -Be 1
        $loginCategoryOutput[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobCategory
        $loginCategoryOutput[0].Name | Should -BeExactly $loginCategoryName
        $loginCategoryOutput[0].JobCount | Should -Be 0
    }

    It "warns without output when SQL credentials are omitted" {
        $loginCategoryWarnings = @()
        $splatLoginCategoryDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Category = $loginCategoryName
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "loginCategoryWarnings"
        }
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentJobCategory.ps1:94-99
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Excerpt route audit: archive/conversions/fleet-manager-20261024/sqllogin-cohort-20261028.txt.
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        @(Get-DbaAgentJobCategory @splatLoginCategoryDenied).Count | Should -Be 0
        $loginCategoryWarnings | Should -Not -BeNullOrEmpty
    }

    It "throws with EnableException when SQL credentials are omitted" {
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgentJobCategory.ps1:94-99
        # The base already ships this cmdlet; the pin predates src/ and cannot build a function baseline.
        # Excerpt route audit: archive/conversions/fleet-manager-20261024/sqllogin-cohort-20261028.txt.
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        { Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSqlLogin -Category $loginCategoryName -EnableException } | Should -Throw
    }
}

Describe "Get-DbaAgentJobCategory Azure SQL Database" -Tag IntegrationTests {
    It "refuses Azure SQL Database before enumerating Agent categories" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $errorException = $_.Exception
                $resuming = $false
                while ($errorException) {
                    if ($errorException.Number -in 40613, -2 -or $errorException -is [System.TimeoutException] -or $errorException.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                    $errorException = $errorException.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Get-DbaAgentJobCategory -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Get-DbaAgentJobCategory -SqlInstance $azure -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { if ($azure) { $azure.ConnectionContext.Disconnect() } }
    }
}
