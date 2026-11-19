#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads the SQL Agent shared schedules.

Describe "Native Get-DbaAgentSchedule" -Tag IntegrationTests {
    BeforeAll {
        $schedInstance = $TestConfig.InstanceSingle
        $schedServer = Connect-DbaInstance -SqlInstance $schedInstance -EnableException
        # Unique per leg and run: the instance is shared.
        $schedPrefix = "dbatoolsci_natsched_" + [Guid]::NewGuid().ToString("N").Substring(0, 10)
        $schedBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $schedListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($schedListeners | Where-Object Port -eq 1).Count) {
            throw "Schedule failure fixture requires no local TCP listener on port 1"
        }
        $schedOwnNames = New-Object System.Collections.Generic.List[string]

        function New-NativeSharedSchedule {
            param($Name, [hashtable]$Settings)
            $newSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule -ArgumentList $schedServer.JobServer, $Name
            # Set explicitly, as New-DbaAgentSchedule does, unless the case names its own.
            $newSchedule.IsEnabled = $true
            $newSchedule.ActiveStartDate = [datetime]"2026-01-01"
            $newSchedule.ActiveEndDate = $openEnd
            foreach ($settingName in $Settings.Keys) {
                $newSchedule.$settingName = $Settings[$settingName]
            }
            $schedOwnNames.Add($Name)
            $newSchedule.Create()
        }

        # The expected text follows the pinned Get-ScheduleDescription with the leg's culture, as the pinned
        # "Monthly schedule is correct" test does.
        $schedFormat = (Get-Culture).DateTimeFormat
        function Get-NativeDateText($Date) { Get-Date $Date -Format $schedFormat.ShortDatePattern }
        function Get-NativeTimeText($Time) { Get-Date $Time -Format $schedFormat.LongTimePattern }
        $openEnd = [datetime]"9999-12-31"

        $schedFixture = @{
            weekly2   = @{
                Name     = $schedPrefix + "_weekly2"
                Settings = @{ FrequencyTypes = "Weekly"; FrequencyInterval = 34; FrequencyRecurrenceFactor = 2; FrequencySubDayTypes = "Hour"; FrequencySubDayInterval = 4; ActiveStartDate = [datetime]"2026-01-05"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"01:00:00"; ActiveEndTimeOfDay = [timespan]"23:00:00" }
                Expected = "Occurs every 2 week(s) on Monday, Friday every 4 hour(s) between " + (Get-NativeTimeText "01:00:00") + " and " + (Get-NativeTimeText "23:00:00") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2026-01-05")) + "."
            }
            weekly1   = @{
                Name     = $schedPrefix + "_weekly1"
                Settings = @{ FrequencyTypes = "Weekly"; FrequencyInterval = 65; FrequencyRecurrenceFactor = 1; FrequencySubDayTypes = "Once"; FrequencySubDayInterval = 0; ActiveStartDate = [datetime]"2026-01-10"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"05:15:00" }
                Expected = "Occurs every week on Saturday, Sunday at " + (Get-NativeTimeText "05:15:00") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2026-01-10")) + "."
            }
            monthrel  = @{
                Name     = $schedPrefix + "_monthrel"
                Settings = @{ FrequencyTypes = "MonthlyRelative"; FrequencyRelativeIntervals = "Second"; FrequencyInterval = 3; FrequencyRecurrenceFactor = 1; FrequencySubDayTypes = "Once"; FrequencySubDayInterval = 0; ActiveStartDate = [datetime]"2026-02-01"; ActiveEndDate = [datetime]"2027-12-31"; ActiveStartTimeOfDay = [timespan]"06:30:00" }
                Expected = "Occurs every second Tuesday of every 1 month(s) at " + (Get-NativeTimeText "06:30:00") + ". Schedule will used between " + (Get-NativeDateText ([datetime]"2026-02-01")) + " and " + (Get-NativeDateText ([datetime]"2027-12-31")) + "."
            }
            daily3    = @{
                Name     = $schedPrefix + "_daily3"
                Settings = @{ FrequencyTypes = "Daily"; FrequencyInterval = 3; FrequencySubDayTypes = "Minute"; FrequencySubDayInterval = 15; ActiveStartDate = [datetime]"2026-03-01"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"08:00:00"; ActiveEndTimeOfDay = [timespan]"17:30:00" }
                Expected = "Occurs every 3 day(s) every 15 minute(s) between " + (Get-NativeTimeText "08:00:00") + " and " + (Get-NativeTimeText "17:30:00") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2026-03-01")) + "."
            }
            daily1    = @{
                Name     = $schedPrefix + "_daily1"
                Settings = @{ FrequencyTypes = "Daily"; FrequencyInterval = 1; FrequencySubDayTypes = "Second"; FrequencySubDayInterval = 30; ActiveStartDate = [datetime]"2026-03-02"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"00:00:00"; ActiveEndTimeOfDay = [timespan]"23:59:59" }
                Expected = "Occurs every day every 30 second(s) between " + (Get-NativeTimeText "00:00:00") + " and " + (Get-NativeTimeText "23:59:59") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2026-03-02")) + "."
            }
            monthly   = @{
                Name     = $schedPrefix + "_monthly"
                Settings = @{ FrequencyTypes = "Monthly"; FrequencyInterval = 10; FrequencyRecurrenceFactor = 3; FrequencySubDayTypes = "Once"; FrequencySubDayInterval = 0; ActiveStartDate = [datetime]"2026-04-01"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"22:00:00" }
                Expected = "Occurs every 3 month(s) on day 10 of that month at " + (Get-NativeTimeText "22:00:00") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2026-04-01")) + "."
            }
            # The pinned text runs "at <time>" straight into the sub-day "at <time>. " for a one-time schedule;
            # kept verbatim (message text is part of the contract).
            once      = @{
                Name     = $schedPrefix + "_once"
                Settings = @{ FrequencyTypes = "OneTime"; FrequencySubDayTypes = "Once"; ActiveStartDate = [datetime]"2027-03-15"; ActiveEndDate = $openEnd; ActiveStartTimeOfDay = [timespan]"12:00:00" }
                Expected = "Occurs on " + (Get-NativeDateText ([datetime]"2027-03-15")) + " at " + (Get-NativeTimeText "12:00:00") + "at " + (Get-NativeTimeText "12:00:00") + ". Schedule will be used starting on " + (Get-NativeDateText ([datetime]"2027-03-15")) + "."
            }
            autostart = @{
                Name     = $schedPrefix + "_autostart"
                Settings = @{ FrequencyTypes = "AutoStart" }
                Expected = "Start automatically when SQL Server Agent starts "
            }
            onidle    = @{
                Name     = $schedPrefix + "_onidle"
                Settings = @{ FrequencyTypes = "OnIdle" }
                Expected = "Start whenever the CPUs become idle"
            }
        }
        foreach ($fixtureKey in $schedFixture.Keys) {
            New-NativeSharedSchedule -Name $schedFixture[$fixtureKey].Name -Settings $schedFixture[$fixtureKey].Settings
        }
        # A schedule whose real name contains a wildcard character, and a sibling that name would match as a pattern.
        $schedLiteralName = $schedPrefix + "_lit*"
        $schedLiteralSibling = $schedPrefix + "_lit_x"
        New-NativeSharedSchedule -Name $schedLiteralName -Settings @{ FrequencyTypes = "OnIdle" }
        New-NativeSharedSchedule -Name $schedLiteralSibling -Settings @{ FrequencyTypes = "OnIdle" }

        $schedServer.JobServer.SharedSchedules.Refresh()
        $schedByName = @{}
        foreach ($sharedSchedule in $schedServer.JobServer.SharedSchedules) {
            if ($sharedSchedule.Name -in $schedOwnNames) { $schedByName[$sharedSchedule.Name] = $sharedSchedule }
        }
    }

    AfterAll {
        if ($schedServer -and $schedOwnNames) {
            $schedServer.JobServer.SharedSchedules.Refresh()
            $schedCleanup = @($schedServer.JobServer.SharedSchedules | Where-Object Name -in $schedOwnNames)
            foreach ($schedDrop in $schedCleanup) { $schedDrop.Drop() }
        }
    }

    Context "Descriptions" {
        It "describes a <Key> schedule with the pinned text" -ForEach @(
            @{ Key = "weekly2" }, @{ Key = "weekly1" }, @{ Key = "monthrel" }, @{ Key = "daily3" }, @{ Key = "daily1" },
            @{ Key = "monthly" }, @{ Key = "once" }, @{ Key = "autostart" }, @{ Key = "onidle" }
        ) {
            $descRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Schedule $schedFixture[$Key].Name -EnableException)
            $descRows.Count | Should -Be 1
            $descRows[0].Description | Should -BeExactly $schedFixture[$Key].Expected
        }
    }

    Context "Output" {
        It "returns the SMO schedule with the instance properties, the ScheduleName alias and the pinned default view" {
            $outRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Schedule $schedFixture.weekly2.Name -EnableException)
            $outRows.Count | Should -Be 1
            $outRow = $outRows[0]
            $outRow.PSObject.BaseObject | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobSchedule
            $outRow.Name | Should -BeExactly $schedFixture.weekly2.Name
            $outRow.ScheduleName | Should -BeExactly $schedFixture.weekly2.Name
            $outRow.PSObject.Properties["ScheduleName"].MemberType | Should -Be "AliasProperty"
            $outRow.ComputerName | Should -BeExactly $schedServer.ComputerName
            $outRow.InstanceName | Should -BeExactly $schedServer.ServiceName
            $outRow.SqlInstance | Should -BeExactly $schedServer.DomainInstanceName
            $outRow.ScheduleUid | Should -Be $schedByName[$schedFixture.weekly2.Name].ScheduleUid
            $outRow.FrequencyTypes | Should -Be "Weekly"
            $outRow.FrequencySubDayTypes | Should -Be "Hour"
            (@($outRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,ScheduleName,ActiveEndDate,ActiveEndTimeOfDay,ActiveStartDate,ActiveStartTimeOfDay,DateCreated,FrequencyInterval,FrequencyRecurrenceFactor,FrequencyRelativeIntervals,FrequencySubDayInterval,FrequencySubDayTypes,FrequencyTypes,IsEnabled,JobCount,Description,ScheduleUid"
        }

        It "returns every shared schedule without a filter" {
            $allRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -EnableException)
            foreach ($ownName in $schedOwnNames) {
                @($allRows | Where-Object Name -eq $ownName).Count | Should -Be 1
            }
        }
    }

    Context "Filters" {
        It "selects by -Schedule name, case-insensitively" {
            $nameRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Schedule $schedFixture.daily3.Name.ToUpperInvariant() -EnableException)
            $nameRows.Count | Should -Be 1
            $nameRows[0].Name | Should -BeExactly $schedFixture.daily3.Name
        }

        It "selects by -ScheduleUid text, case-insensitively" {
            $uidText = $schedByName[$schedFixture.monthly.Name].ScheduleUid.ToString().ToUpperInvariant()
            $uidRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -ScheduleUid $uidText -EnableException)
            $uidRows.Count | Should -Be 1
            $uidRows[0].Name | Should -BeExactly $schedFixture.monthly.Name
        }

        It "selects by -Id" {
            $idRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Id $schedByName[$schedFixture.once.Name].ID -EnableException)
            $idRows.Count | Should -Be 1
            $idRows[0].Name | Should -BeExactly $schedFixture.once.Name
        }

        It "appends the -Schedule, then -ScheduleUid, then -Id matches" {
            $splatUnion = @{
                SqlInstance     = $schedInstance
                Id              = $schedByName[$schedFixture.daily1.Name].ID
                ScheduleUid     = $schedByName[$schedFixture.monthrel.Name].ScheduleUid.ToString()
                Schedule        = $schedFixture.autostart.Name
                EnableException = $true
            }
            $unionRows = @(Get-DbaAgentSchedule @splatUnion)
            ($unionRows.Name -join ",") | Should -BeExactly ($schedFixture.autostart.Name + "," + $schedFixture.monthrel.Name + "," + $schedFixture.daily1.Name)
        }
    }

    Context "Pipeline, failures and errors" {
        It "returns the schedules of each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $pipedRows = @($schedInstance, $schedInstance | Get-DbaAgentSchedule -Schedule $schedFixture.onidle.Name -EnableException)
            $pipedRows.Count | Should -Be 2
        }

        It "warns and continues past an instance that cannot be reached" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $reachWarnings = @()
            $reachRows = @(Get-DbaAgentSchedule -SqlInstance $schedBadInstance, $schedInstance -Schedule $schedFixture.onidle.Name -EnableException:$false -WarningAction SilentlyContinue -WarningVariable reachWarnings)
            $reachRows.Count | Should -Be 1
            $reachRows[0].Name | Should -BeExactly $schedFixture.onidle.Name
            "$reachWarnings" | Should -BeLike "*Failure*"
        }

        It "throws a connection error with EnableException" -Tag "NativeChecklist:enable-exception" {
            $reachFailure = $null
            try {
                $null = Get-DbaAgentSchedule -SqlInstance $schedBadInstance -EnableException
            } catch {
                $reachFailure = $PSItem
            }
            $reachFailure | Should -Not -BeNullOrEmpty
            $reachFailure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAgentSchedule*"
            $reachFailure.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "Upstream corrections" {
        It "returns every schedule a -Schedule wildcard matches, as its help documents" {
            $patternRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Schedule ($schedPrefix + "_WEEKLY?"), ($schedPrefix + "_daily*") -EnableException)
            (@($patternRows.Name | Sort-Object) -join ",") | Should -BeExactly ((@($schedFixture.daily1.Name, $schedFixture.daily3.Name, $schedFixture.weekly1.Name, $schedFixture.weekly2.Name) | Sort-Object) -join ",")
        }

        It "keeps a -Schedule value literal when a schedule has that exact name" {
            $literalRows = @(Get-DbaAgentSchedule -SqlInstance $schedInstance -Schedule $schedLiteralName -EnableException)
            $literalRows.Count | Should -Be 1
            $literalRows[0].Name | Should -BeExactly $schedLiteralName
        }

        # NativeChecklist: azure-sqldb -- SQL Server Agent and msdb do not exist in Azure SQL Database (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server, "SQL Server Agent: Syntax that relies upon the SQL Server Agent or the msdb database"); the command refuses it as Connect-DbaInstance -AzureUnsupported does.
        It "refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does" -Tag "NativeChecklist:azure-sqldb" {
            $azure = $null
            for ($attempt = 0; $attempt -lt 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                    break
                } catch {
                    $transient = $false
                    for ($failure = $PSItem.Exception; $failure; $failure = $failure.InnerException) {
                        if ($failure.Number -in @(-2, 40613) -or $failure.Message -match "timed out|timeout") { $transient = $true }
                    }
                    if (-not $transient -or $attempt -eq 5) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaAgentSchedule -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaAgentSchedule -SqlInstance $azure -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        }
    }
}

Describe "Native Get-DbaAgentSchedule over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginScheduleName = "dbatoolsci_natsched_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule -ArgumentList $loginServer.JobServer, $loginScheduleName
            $loginSchedule.IsEnabled = $true
            $loginSchedule.FrequencyTypes = "OnIdle"
            $loginSchedule.ActiveStartDate = [datetime]"2026-01-01"
            $loginSchedule.ActiveEndDate = [datetime]"9999-12-31"
            $loginSchedule.Create()
        }
        AfterAll {
            if ($loginServer -and $loginScheduleName) {
                $loginServer.JobServer.SharedSchedules.Refresh()
                $loginCleanup = @($loginServer.JobServer.SharedSchedules | Where-Object Name -eq $loginScheduleName)
                foreach ($loginDrop in $loginCleanup) { $loginDrop.Drop() }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginSchedule = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Schedule        = $loginScheduleName
                EnableException = $true
            }
            $loginRows = @(Get-DbaAgentSchedule @splatLoginSchedule)
            $loginRows.Count | Should -Be 1
            $loginRows[0].ScheduleName | Should -BeExactly $loginScheduleName
            $loginRows[0].Description | Should -BeExactly "Start whenever the CPUs become idle"
        }

        # Pin public/Get-DbaAgentSchedule.ps1:289-294 (refs/pins/dbatools-2026-10-22), verbatim:
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        # Connect-DbaInstance forces its own EnableException, so a failed login throws into this catch: a warning and no
        # output by default, a terminating error under -EnableException. No commit can run the pinned function: the base
        # ships the compiled cmdlet and the pin predates src/, so these assertions follow this excerpt (watchman 49f13ebb).
        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Schedule        = $loginScheduleName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaAgentSchedule @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAgentSchedule -SqlInstance $loginInstance -Schedule $loginScheduleName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
