#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSsisCatalog",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess at High impact" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
            $cmdletAttribute = (Get-Command $CommandName).ImplementingType.GetCustomAttributes([System.Management.Automation.CmdletAttribute], $false)[0]
            $cmdletAttribute.SupportsShouldProcess | Should -BeTrue
            $cmdletAttribute.ConfirmImpact | Should -Be "High"
        }

        It "Should take the instance as a mandatory pipeline parameter" {
            # There is no -InputObject here - the catalog has no name parameter and no object to
            # pipe - so the #974 constraint that keeps SqlInstance off the pipeline elsewhere in
            # this module does not apply, and the instance is what pipes in.
            $sqlInstance = (Get-Command $CommandName).Parameters["SqlInstance"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $sqlInstance.Mandatory | Should -BeTrue
            $sqlInstance.ValueFromPipeline | Should -BeTrue
            $sqlInstance.Position | Should -Be 0
        }

        It "Should take Force as a switch" {
            (Get-Command $CommandName).Parameters["Force"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        $referenceFolder = "dbatoolsci_charfolder"

        function Get-SsisCatalogCount {
            $splatPresence = @{
                SqlInstance = $TestConfig.InstanceSsis
                Database    = "master"
                Query       = "SELECT COUNT(*) AS CatalogCount FROM sys.databases WHERE name = N'SSISDB'"
            }
            [int](Invoke-DbaQuery @splatPresence).CatalogCount
        }

        function Get-SsisCatalogUserAccess {
            # 0 MULTI_USER, 1 SINGLE_USER, 2 RESTRICTED_USER.
            $splatUserAccess = @{
                SqlInstance = $TestConfig.InstanceSsis
                Database    = "master"
                Query       = "SELECT user_access FROM sys.databases WHERE name = N'SSISDB'"
            }
            [int](Invoke-DbaQuery @splatUserAccess).user_access
        }

        function Get-SsisReferenceFolderCount {
            $splatReferenceFolder = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS FolderCount FROM [catalog].[folders] WHERE name = @folderName"
                SqlParameter = @{ folderName = "dbatoolsci_charfolder" }
            }
            [int](Invoke-DbaQuery @splatReferenceFolder).FolderCount
        }

        function Get-SsisCatalogDeployProbeCount {
            # Every [catalog] view and every table behind it is plain T-SQL, so they all come back
            # from a RESTORE whether or not the catalog still works. The deploy path is the only
            # thing that loads the ISSERVER assembly and the dependencies it pulls in, and that is
            # exactly what a catalog can silently lose while the row counts stay green. So the
            # probe redeploys the reference project's own bytes - no SSDT needed to build an
            # .ispac, they are already in the catalog - into a throwaway folder and drops it again.
            # The project name has to match the one inside the manifest or the catalog refuses it.
            $probeQuery = @"
SET NOCOUNT ON;
DECLARE @probeFolder sysname = N'dbatoolsci_ssisclrprobe';
IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @probeFolder)
    EXEC [catalog].[delete_project] @folder_name = @probeFolder, @project_name = N'dbatoolsci_charproject';
IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @probeFolder)
    EXEC [catalog].[delete_folder] @folder_name = @probeFolder;
DECLARE @stream varbinary(max);
DECLARE @streams TABLE (project_stream varbinary(max));
INSERT INTO @streams EXEC [catalog].[get_project] @folder_name = N'dbatoolsci_charfolder', @project_name = N'dbatoolsci_charproject';
SELECT @stream = project_stream FROM @streams;
EXEC [catalog].[create_folder] @folder_name = @probeFolder, @folder_id = NULL;
DECLARE @operationId bigint;
EXEC [catalog].[deploy_project] @folder_name = @probeFolder, @project_name = N'dbatoolsci_charproject', @project_stream = @stream, @operation_id = @operationId OUTPUT;
SELECT COUNT(*) AS DeployedCount FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @probeFolder;
EXEC [catalog].[delete_project] @folder_name = @probeFolder, @project_name = N'dbatoolsci_charproject';
EXEC [catalog].[delete_folder] @folder_name = @probeFolder;
"@

            $splatDeployProbe = @{
                SqlInstance = $TestConfig.InstanceSsis
                Database    = "SSISDB"
                Query       = $probeQuery
            }
            [int](Invoke-DbaQuery @splatDeployProbe).DeployedCount
        }

        # This suite destroys the lab's SSIS catalog on purpose, and every other SSIS suite reads
        # its fixtures out of that catalog - the reference project's .ispac only exists inside it,
        # because there is no SSDT on the runner to build another one. The backup is the way back,
        # so it is taken before anything else and its success is asserted here rather than
        # discovered in AfterAll when it is too late to do anything about it.
        if ((Get-SsisCatalogCount) -eq 0) {
            throw "SSISDB is absent from $ssisInstance before this suite has run - restore the lab SSIS fixture first (migration issue #972)"
        }

        $splatCatalogBackup = @{
            SqlInstance    = $ssisInstance
            Database       = "SSISDB"
            Type           = "Full"
            BackupFileName = "dbatoolsci_ssiscatalog_removal.bak"
            Initialize     = $true
            CopyOnly       = $true
        }
        $catalogBackup = Backup-DbaDatabase @splatCatalogBackup
        if (-not $catalogBackup.BackupComplete) {
            throw "the SSISDB safety backup did not complete; refusing to run a suite that drops the catalog"
        }
        $catalogBackupPath = $catalogBackup.FullName

        $catalogBefore = @(Get-DbaSsisCatalog -SqlInstance $ssisInstance)[0]

        # The reference folder is what every "and the contents survived" assertion below is made
        # against, so its absence is refused up front rather than allowed to turn those legs into
        # 0-equals-0.
        if ((Get-SsisReferenceFolderCount) -ne 1) {
            throw "the lab reference folder $referenceFolder is missing from the SSIS catalog on $ssisInstance - restore the lab SSIS fixture first (migration issue #972)"
        }

        # Held open for the whole suite: the no-Force leg needs something connected to SSISDB for
        # the server to refuse the drop over, and the -Force leg needs that same connection still
        # there so that what -Force disconnects is a real session rather than an empty claim.
        $splatCatalogHolder = @{
            SqlInstance         = $ssisInstance
            Database            = "SSISDB"
            NonPooledConnection = $true
        }
        $catalogHolder = Connect-DbaInstance @splatCatalogHolder
        $catalogHolder.ConnectionContext.Connect()
        $catalogHolderSpid = $catalogHolder.ConnectionContext.ProcessID
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        if ($catalogHolder) {
            # The database this connection opened against is gone by now, so tearing it down is
            # allowed to complain; what matters is that the restore below still runs.
            try {
                $catalogHolder.ConnectionContext.Disconnect()
            } catch {
                Write-Warning "could not close the SSISDB holder connection: $PSItem"
            }
        }

        if ((Get-SsisCatalogCount) -eq 0) {
            $splatCatalogRestore = @{
                SqlInstance  = $ssisInstance
                Path         = $catalogBackupPath
                DatabaseName = "SSISDB"
            }
            $null = Restore-DbaDatabase @splatCatalogRestore

            # RESTORE resets TRUSTWORTHY to OFF, and the catalog's own procedures need it on.
            $splatTrustworthy = @{
                SqlInstance = $ssisInstance
                Database    = "master"
                Query       = "ALTER DATABASE [SSISDB] SET TRUSTWORTHY ON;"
            }
            Invoke-DbaQuery @splatTrustworthy

            # RESTORE also hands the database to whoever restored it, and a catalog owned by the
            # runner account instead of sa was measured on this lab with its CLR dead and every
            # deploy failing on an assembly load, while everything the usual checklist looks at -
            # TRUSTWORTHY, clr enabled, the ISSERVER hash in sys.trusted_assemblies - read correct.
            $splatCatalogOwner = @{
                SqlInstance = $ssisInstance
                Database    = "master"
                Query       = "ALTER AUTHORIZATION ON DATABASE::[SSISDB] TO [sa];"
            }
            Invoke-DbaQuery @splatCatalogOwner

            # Tidies up executions the drop left mid-flight. Not fatal if it complains - the
            # assertions below are what say whether the fixture is actually back.
            $splatCatalogStartup = @{
                SqlInstance     = $ssisInstance
                Database        = "SSISDB"
                Query           = "EXEC [catalog].[startup];"
                EnableException = $false
                ErrorAction     = "SilentlyContinue"
            }
            Invoke-DbaQuery @splatCatalogStartup
        }

        # A restore that silently did not happen would leave the next SSIS suite failing for a
        # reason nothing points at, so this is asserted rather than attempted.
        Get-SsisCatalogCount | Should -Be 1
        Get-SsisReferenceFolderCount | Should -Be 1

        # Those two count rows a RESTORE always brings back, so they are the one thing here that
        # cannot fail - they stayed green against a catalog whose CLR-backed procedures were all
        # dead, and the next SSIS suite inherited it with nothing pointing at the cause. This one
        # actually deploys, so it goes red when the catalog is back in name only.
        Get-SsisCatalogDeployProbeCount | Should -Be 1
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and drops nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisCatalog @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisCatalog @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }

    Context "-WhatIf" {
        It "Reports without dropping the catalog" {
            # The assertion that matters is the database afterwards, not the message: this is the
            # one command in the module where a -WhatIf that leaked would destroy everything the
            # rest of the SSIS suites read from.
            $whatIfResult = @(Remove-DbaSsisCatalog -SqlInstance $ssisInstance -WhatIf)
            $whatIfResult.Count | Should -Be 0
            Get-SsisCatalogCount | Should -Be 1
        }

        It "Leaves the catalog's contents alone as well as the database" {
            $null = Remove-DbaSsisCatalog -SqlInstance $ssisInstance -Force -WhatIf
            Get-SsisCatalogCount | Should -Be 1
            Get-SsisReferenceFolderCount | Should -Be 1
            # -Force under -WhatIf must not have run the SINGLE_USER half either; a catalog left
            # single-user is unusable even though the database is still standing.
            Get-SsisCatalogUserAccess | Should -Be 0
        }
    }

    Context "A catalog that is in use" {
        It "Reports the server's refusal and changes nothing without -Force" {
            # The holder is asserted alive first. Without that this leg would pass just as well
            # against a catalog nothing was connected to, and would prove nothing about -Force.
            $splatHolderAlive = @{
                SqlInstance  = $ssisInstance
                Database     = "master"
                Query        = "SELECT COUNT(*) AS SessionCount FROM sys.dm_exec_sessions WHERE session_id = @spid AND database_id = DB_ID('SSISDB')"
                SqlParameter = @{ spid = $catalogHolderSpid }
            }
            [int](Invoke-DbaQuery @splatHolderAlive).SessionCount | Should -Be 1

            $splatInUse = @{
                SqlInstance     = $ssisInstance
                EnableException = $false
                WarningVariable = "inUseWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisCatalog @splatInUse)
            $none.Count | Should -Be 0
            ($inUseWarnings -join " ") | Should -BeLike "*Failure removing the SSIS catalog*"
            ($inUseWarnings -join " ") | Should -BeLike "*currently in use*"
            Get-SsisCatalogCount | Should -Be 1
            Get-SsisReferenceFolderCount | Should -Be 1
            # A failed drop that had run the SINGLE_USER half anyway would leave the catalog
            # unreachable, which is worse than not having tried.
            Get-SsisCatalogUserAccess | Should -Be 0
        }

        It "Throws the same refusal under -EnableException" {
            $splatInUseThrow = @{
                SqlInstance     = $ssisInstance
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisCatalog @splatInUseThrow } | Should -Throw "*currently in use*"
            Get-SsisCatalogCount | Should -Be 1
            Get-SsisCatalogUserAccess | Should -Be 0
        }
    }

    Context "Dropping the catalog" {
        It "Drops it with -Force past the session that refused it, and keeps going past an instance with no catalog" {
            # Two things at once, because they need the same one-shot fixture. The no-catalog
            # instance is piped FIRST, so a command whose per-instance failure latched instead of
            # continuing would leave the catalog standing and still look like a clean run. And the
            # holder from the previous context is still connected, so this is the same drop that
            # was refused a moment ago - the only thing that changed is -Force.
            $splatForcedDrop = @{
                Force           = $true
                EnableException = $false
                WarningVariable = "dropWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $dropped = @($TestConfig.InstanceSingle, $ssisInstance | Remove-DbaSsisCatalog @splatForcedDrop)

            ($dropWarnings -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
            $dropped.Count | Should -Be 1
            $dropped[0].Name | Should -Be "SSISDB"
            $dropped[0].Status | Should -Be "Dropped"
            $dropped[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisCatalog"
            $dropped[0].SqlInstance | Should -Be $catalogBefore.SqlInstance
            $dropped[0].SchemaVersion | Should -Be $catalogBefore.SchemaVersion

            Get-SsisCatalogCount | Should -Be 0
        }

        It "Reports the now-absent catalog on a second call instead of dropping again" {
            $splatSecondDrop = @{
                SqlInstance     = $ssisInstance
                Force           = $true
                EnableException = $false
                WarningVariable = "secondWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisCatalog @splatSecondDrop)
            $none.Count | Should -Be 0
            ($secondWarnings -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }
    }
}
