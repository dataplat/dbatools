#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSystemDbUserObject",
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
                "Force",
                "Classic",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        # Source and Destination carry ValidateNotNullOrEmpty on top of Mandatory. Mandatory alone
        # already rejects these arguments, so only the FullyQualifiedErrorId tells the two apart:
        # the validator raises plain ParameterArgumentValidationError, while the binder's own
        # refusal raises ParameterArgumentValidationErrorNullNotAllowed or ...EmptyArrayNotAllowed.
        # Comparing the whole id would not work - it ends in the function name before the flip and
        # the cmdlet type name after it - so the leading token is the assertion.
        It "Should reject a null Source with a validation error rather than a binder refusal" {
            $splatNullSource = @{
                Source      = $null
                Destination = "srv"
                WhatIf      = $true
            }
            $caughtNullSource = $null
            try {
                Copy-DbaSystemDbUserObject @splatNullSource
            } catch {
                $caughtNullSource = $PSItem
            }
            $caughtNullSource | Should -Not -BeNullOrEmpty
            ($caughtNullSource.FullyQualifiedErrorId -split ",")[0] | Should -Be "ParameterArgumentValidationError"
        }

        It "Should reject an empty Destination array with a validation error rather than a binder refusal" {
            $splatEmptyDestination = @{
                Source      = "srv"
                Destination = @()
                WhatIf      = $true
            }
            $caughtEmptyDestination = $null
            try {
                Copy-DbaSystemDbUserObject @splatEmptyDestination
            } catch {
                $caughtEmptyDestination = $PSItem
            }
            $caughtEmptyDestination | Should -Not -BeNullOrEmpty
            ($caughtEmptyDestination.FullyQualifiedErrorId -split ",")[0] | Should -Be "ParameterArgumentValidationError"
        }

        It "Should reject a null element in Destination with a validation error rather than a binder refusal" {
            $splatNullElement = @{
                Source      = "srv"
                Destination = @($null)
                WhatIf      = $true
            }
            $caughtNullElement = $null
            try {
                Copy-DbaSystemDbUserObject @splatNullElement
            } catch {
                $caughtNullElement = $PSItem
            }
            $caughtNullElement | Should -Not -BeNullOrEmpty
            ($caughtNullElement.FullyQualifiedErrorId -split ",")[0] | Should -Be "ParameterArgumentValidationError"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Run setup with EnableException so a broken fixture fails the run instead of quietly
        # leaving the legs below asserting against nothing.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $objSchema = "dbatoolsci_sysobj_schema"
        $objTable  = "dbatoolsci_sysobj_table"
        $objProc   = "dbatoolsci_sysobj_proc"
        $objView   = "dbatoolsci_sysobj_view"
        $objFunc   = "dbatoolsci_sysobj_fn"
        # Copied only by the -WhatIf leg, so it must not exist on the destination until the
        # control leg that follows creates it for real.
        $objLater  = "dbatoolsci_sysobj_later"

        $procMarker      = "marker-original"
        $procForceMarker = "marker-after-force"

        # This command copies EVERY user object out of master, model and msdb, so a run picks up
        # whatever else is sitting in those databases. Every assertion below filters to the names
        # created here; a bare count would measure the lab, not the command.
        $splatCleanup = @{
            Database = "master"
            Query    = "
IF OBJECT_ID('dbo.$objView') IS NOT NULL DROP VIEW dbo.$objView;
IF OBJECT_ID('dbo.$objProc') IS NOT NULL DROP PROCEDURE dbo.$objProc;
IF OBJECT_ID('dbo.$objLater') IS NOT NULL DROP PROCEDURE dbo.$objLater;
IF OBJECT_ID('dbo.$objFunc') IS NOT NULL DROP FUNCTION dbo.$objFunc;
IF OBJECT_ID('dbo.$objTable') IS NOT NULL DROP TABLE dbo.$objTable;
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$objSchema') DROP SCHEMA [$objSchema];"
        }
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            $null = Invoke-DbaQuery -SqlInstance $instance @splatCleanup
        }

        # Fixtures live in master on the source only. The schema is separate from the table on
        # purpose - it exercises the Schemas branch, which scripts through a different SMO Transfer
        # path than the Tables branch.
        $splatFixture = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Database    = "master"
        }
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE SCHEMA [$objSchema]"
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE TABLE dbo.$objTable (Id int NOT NULL PRIMARY KEY, Payload nvarchar(50) NULL)"
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE PROCEDURE dbo.$objProc AS SELECT '$procMarker' AS Marker"
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE PROCEDURE dbo.$objLater AS SELECT 'later' AS Marker"
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE VIEW dbo.$objView AS SELECT 1 AS One"
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE FUNCTION dbo.$objFunc (@n int) RETURNS int AS BEGIN RETURN @n + 1 END"
    }

    AfterAll {
        # Fail loudly. These fixtures live in master on a shared instance, so cleanup that failed
        # quietly would leave them behind for the next suite to copy and miscount.
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            $null = Invoke-DbaQuery -SqlInstance $instance @splatCleanup -EnableException
        }
    }

    Context "When previewing with -WhatIf" {
        BeforeAll {
            $splatWhatIf = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                WhatIf      = $true
            }
            $whatIfResults = @(Copy-DbaSystemDbUserObject @splatWhatIf)

            $splatProbeLater = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT OBJECT_ID('dbo.$objLater') AS ObjectId"
            }
            $laterAfterWhatIf = (Invoke-DbaQuery @splatProbeLater).ObjectId
        }

        It "Should emit nothing" {
            $whatIfResults.Count | Should -Be 0
        }

        It "Should not create the object on the destination" {
            # The absence assertion is only worth anything because the copy context below runs the
            # same command against the same fixtures and does create this object.
            $laterAfterWhatIf | Should -BeNullOrEmpty
        }
    }

    Context "When copying user objects to another instance" {
        BeforeAll {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
            }
            $copyResults = @(Copy-DbaSystemDbUserObject @splatCopy)

            $splatProbe = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
            }
            $destProcBody = (Invoke-DbaQuery @splatProbe -Query "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$objProc')) AS Definition").Definition
            $destTableId  = (Invoke-DbaQuery @splatProbe -Query "SELECT OBJECT_ID('dbo.$objTable') AS ObjectId").ObjectId
            $destLaterId  = (Invoke-DbaQuery @splatProbe -Query "SELECT OBJECT_ID('dbo.$objLater') AS ObjectId").ObjectId
            $destSchemaId = (Invoke-DbaQuery @splatProbe -Query "SELECT schema_id AS SchemaId FROM sys.schemas WHERE name = '$objSchema'").SchemaId
        }

        It "Should report the schema copied successfully" {
            $schemaRow = @($copyResults | Where-Object { "$($PSItem.Name)" -eq $objSchema })
            $schemaRow.Count | Should -Be 1
            $schemaRow[0].Status | Should -Be "Successful"
            $schemaRow[0].Type | Should -Be "User schema in master"
        }

        It "Should land the schema on the destination" {
            $destSchemaId | Should -Not -BeNullOrEmpty
        }

        It "Should report the table copied successfully" {
            $tableRow = @($copyResults | Where-Object { "$($PSItem.Name)" -like "*$objTable*" })
            $tableRow.Count | Should -Be 1
            $tableRow[0].Status | Should -Be "Successful"
            $tableRow[0].Type | Should -Be "User table in master"
        }

        It "Should land the table on the destination" {
            $destTableId | Should -Not -BeNullOrEmpty
        }

        It "Should land the procedure body on the destination" {
            # Matched against this procedure's own marker: the body reuses $sql, $name and $type
            # across the per-object loop, so a stale capture would write one object's definition
            # under another object's name, and only a marker read back can see that.
            $destProcBody | Should -Match $procMarker
        }

        It "Should create the object the -WhatIf leg declined to create" {
            $destLaterId | Should -Not -BeNullOrEmpty
        }

        It "Should map each module type to its friendly type name" {
            # get-sqltypename lives in the source's begin block. If it goes missing the Type cell
            # renders as a bare " in master", so these assertions are what pins that helper - and
            # they cover three different arms of its switch.
            $procRow = @($copyResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objProc]" })
            $procRow.Count | Should -Be 1
            $procRow[0].Type | Should -Be "User stored procedure in master"

            $viewRow = @($copyResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objView]" })
            $viewRow.Count | Should -Be 1
            $viewRow[0].Type | Should -Be "view in master"

            $funcRow = @($copyResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objFunc]" })
            $funcRow.Count | Should -Be 1
            $funcRow[0].Type | Should -Be "User scalar function in master"
        }

        It "Should carry both server names on every emitted row" {
            $mineRows = @($copyResults | Where-Object { "$($PSItem.Name)" -like "*dbatoolsci_sysobj*" })
            $mineRows.Count | Should -BeGreaterThan 0
            @($mineRows | Where-Object { -not $PSItem.SourceServer -or -not $PSItem.DestinationServer }).Count | Should -Be 0
        }
    }

    Context "When the objects already exist on the destination" {
        BeforeAll {
            $splatRecopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
            }
            $recopyResults = @(Copy-DbaSystemDbUserObject @splatRecopy)
        }

        It "Should report the procedure skipped rather than copying it again" {
            $procRow = @($recopyResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objProc]" })
            $procRow.Count | Should -Be 1
            $procRow[0].Status | Should -Be "Skipped"
            $procRow[0].Notes | Should -Be "Already exists on destination"
        }

        It "Should report the table skipped rather than copying it again" {
            $tableRow = @($recopyResults | Where-Object { "$($PSItem.Name)" -like "*$objTable*" })
            $tableRow.Count | Should -Be 1
            $tableRow[0].Status | Should -Be "Skipped"
            $tableRow[0].Notes | Should -Be "Already exists on destination"
        }
    }

    Context "When -Force is used after the source object changed" {
        BeforeAll {
            $splatAlter = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "ALTER PROCEDURE dbo.$objProc AS SELECT '$procForceMarker' AS Marker"
            }
            $null = Invoke-DbaQuery @splatAlter

            $splatForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Force       = $true
            }
            $forceResults = @(Copy-DbaSystemDbUserObject @splatForce)

            $splatProbeForced = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$objProc')) AS Definition"
            }
            $forcedProcBody = (Invoke-DbaQuery @splatProbeForced).Definition
        }

        It "Should report the procedure copied rather than skipped" {
            $procRow = @($forceResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objProc]" })
            $procRow.Count | Should -Be 1
            $procRow[0].Status | Should -Be "Successful"
        }

        It "Should replace the destination body with the new one" {
            # Both halves asserted: the new marker arrived AND the old one is gone. Matching only
            # the new marker would pass against a destination that still held both definitions.
            $forcedProcBody | Should -Match $procForceMarker
            $forcedProcBody | Should -Not -Match $procMarker
        }
    }

    Context "When more than one destination is given" {
        BeforeAll {
            # The source is also a destination here, which is the only two-destination pair this
            # lab can build. It still walks the foreach over $Destination twice, and the two passes
            # take different paths - already present on the source, copied on the other - so a body
            # that read a destination-scoped variable assigned on the previous pass would surface
            # as the wrong DestinationServer on one of the rows.
            $splatMulti = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
            }
            $multiResults = @(Copy-DbaSystemDbUserObject @splatMulti)
            $procRows = @($multiResults | Where-Object { "$($PSItem.Name)" -eq "[dbo].[$objProc]" })
        }

        It "Should emit one row per destination for the same object" {
            $procRows.Count | Should -Be 2
        }

        It "Should name a distinct destination server on each row" {
            @($procRows.DestinationServer | Sort-Object -Unique).Count | Should -Be 2
        }
    }

    Context "When -Classic is used" {
        BeforeAll {
            $splatClassicCleanup = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "IF OBJECT_ID('dbo.$objProc') IS NOT NULL DROP PROCEDURE dbo.$objProc"
            }
            $null = Invoke-DbaQuery @splatClassicCleanup

            $splatClassic = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Classic     = $true
            }
            $classicResults = @(Copy-DbaSystemDbUserObject @splatClassic)

            $splatProbeClassic = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT OBJECT_ID('dbo.$objProc') AS ObjectId"
            }
            $classicProcId = (Invoke-DbaQuery @splatProbeClassic).ObjectId
        }

        It "Should still copy the object" {
            # The positive half. Without it the emit assertion below would also be satisfied by a
            # branch that did nothing at all.
            $classicProcId | Should -Not -BeNullOrEmpty
        }

        It "Should emit no migration status rows" {
            # The whole discriminator between the two branches: the default path emits one
            # MigrationObject per object, the Classic bulk path emits none.
            #
            # Nulls are filtered rather than counted. The Classic path runs each scripted statement
            # through the Server.Query type extension, which ends in $dataSet.Tables[0]; a DDL batch
            # comes back with zero tables, so that index yields $null and PowerShell puts it on the
            # pipeline. @($null).Count is 1, so a bare count assertion here reds on an artifact that
            # is identical either side of the flip. Filtering keeps the leg strict about real output
            # - any object at all fails it - without pinning that upstream wart.
            @($classicResults | Where-Object { $null -ne $PSItem }).Count | Should -Be 0
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path

            # The probe is written and then executed as a script, so it gets a directory of its
            # own rather than a guessable name in shared temp: New-Item -ItemType Directory fails
            # if the name is taken, which makes the create the exclusive step. Otherwise a peer
            # window - or anything else on this box - could win the race between the write and the
            # run and decide what this shell executes.
            $probeRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("n"))"
            $splatProbeRoot = @{
                Path        = $probeRoot
                ItemType    = "Directory"
                ErrorAction = "Stop"
            }
            $null = New-Item @splatProbeRoot
            $probePath = Join-Path -Path $probeRoot -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there. The
            # alias is probed in the same shell because the psm1 registers it against the command
            # NAME, and nothing else in the suite would notice it breaking on the flip.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaSystemDbUserObject -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Copy-DbaSystemDbUserObject -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
`$aliasTarget = (Get-Command -Name Copy-DbaSysDbUserObject -ErrorAction SilentlyContinue).ResolvedCommand.Name
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded|`$aliasTarget"
"@
            $splatProbeBody = @{
                Path     = $probePath
                Value    = $probeBody
                Encoding = "UTF8"
            }
            Set-Content @splatProbeBody

            $probeOutput = & $shellPath -NoProfile -NonInteractive -File $probePath 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            $splatProbeCleanup = @{
                Path        = $probeRoot
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatProbeCleanup
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }

        It "Should keep the Copy-DbaSysDbUserObject alias pointing at the command" {
            $probeFields[5] | Should -Be "Copy-DbaSystemDbUserObject"
        }
    }
}
