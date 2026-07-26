#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaCustomError",
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
                "CustomError",
                "ExcludeCustomError",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # 60000 carries two languages on purpose: the command builds one us_english-first list and
        # reads the destination collection once per destination, so a single call has to create both
        # rows. 60001 is single-language and exists only to give the exclusion filter a second ID to
        # keep.
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -Database master
        foreach ($messageId in 60000, 60001) {
            $sourceServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = $messageId) EXEC sp_dropmessage @msgnum = $messageId, @lang = 'all'")
        }
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'The item named %s already exists in %s.', @lang = 'us_english'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!', @lang = 'French'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60001, @severity = 16, @msgtext = N'The second item named %s already exists.', @lang = 'us_english'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serversToClean = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
        foreach ($serverInstance in $serversToClean) {
            $cleanupServer = Connect-DbaInstance -SqlInstance $serverInstance -Database master
            foreach ($messageId in 60000, 60001) {
                $cleanupServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = $messageId) EXEC sp_dropmessage @msgnum = $messageId, @lang = 'all'") | Out-Null
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying custom errors" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -Database master
            foreach ($messageId in 60000, 60001) {
                $destServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = $messageId) EXEC sp_dropmessage @msgnum = $messageId, @lang = 'all'")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should successfully copy custom error messages" {
            $splatCopyError = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $copyResults = Copy-DbaCustomError @splatCopyError
            $copyResults.Name[0] | Should -Be "60000:'us_english'"
            $copyResults.Name[1] | Should -Match "60000\:'Fran"
            $copyResults.Status | Should -Be @("Successful", "Successful")
        }

        It "Should land both language rows on the destination from one call" {
            # The cross-record leg. The destination collection is read once, before the loop, and
            # the creates go out as T-SQL, so it never learns about the us_english row this same
            # call just made - which is the only reason the translation is created instead of being
            # reported as already existing. Reading sys.messages off the destination is what proves
            # both rows are really there; the status objects alone cannot.
            $splatCopyBoth = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $bothResults = @(Copy-DbaCustomError @splatCopyBoth)

            $landedRows = @($destServer.Query("SELECT message_id, language_id FROM sys.messages WHERE message_id = 60000 ORDER BY language_id"))
            $landedRows.Count | Should -Be 2
            $landedRows.language_id | Should -Be @(1033, 1036)

            # Two status objects, each preceded by the null the destination Query returns - the
            # create's empty result set is not suppressed.
            $bothResults.Count | Should -Be 4
            @($bothResults | Where-Object { $null -ne $PSItem }).Count | Should -Be 2
        }

        It "Should skip existing custom errors" {
            $splatFirstCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            Copy-DbaCustomError @splatFirstCopy

            $splatSecondCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $skipResults = Copy-DbaCustomError @splatSecondCopy
            $skipResults.Name[0] | Should -Be "60000:'us_english'"
            $skipResults.Name[1] | Should -Match "60000\:'Fran"
            $skipResults.Status | Should -Be @("Skipped", "Skipped")
        }

        It "Should not create anything on the destination with -WhatIf" {
            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CustomError   = 60000
                WhatIf        = $true
                WarningAction = "SilentlyContinue"
            }
            $whatIfResults = @(Copy-DbaCustomError @splatWhatIf)
            $whatIfResults.Count | Should -Be 0

            $rowsAfterWhatIf = @($destServer.Query("SELECT message_id FROM sys.messages WHERE message_id = 60000"))
            $rowsAfterWhatIf.Count | Should -Be 0
        }

        It "Should honor -ExcludeCustomError when a -CustomError list is supplied" {
            $splatExclude = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                CustomError        = 60000, 60001
                ExcludeCustomError = 60000
            }
            $excludeResults = @(Copy-DbaCustomError @splatExclude | Where-Object { $null -ne $PSItem })
            $excludeResults.Status | Should -Be "Successful"
            "$($excludeResults.Name)" | Should -Be "60001:'us_english'"

            @($destServer.Query("SELECT message_id FROM sys.messages WHERE message_id = 60000")).Count | Should -Be 0
            @($destServer.Query("SELECT message_id FROM sys.messages WHERE message_id = 60001")).Count | Should -Be 1
        }

        It "Should report the SMO drop failure and leave nothing behind with -Force" {
            # Measured behaviour of the shipping command against the lab copy pair, not the intent
            # of -Force: SMO's UserDefinedMessage.Drop() removes the row server-side and then
            # throws, so every language row comes back Failed and the recreate never runs. Pinned
            # here so a port that quietly changed it reds; the underlying defect belongs to the
            # source and is registered, not fixed by the port.
            $splatSeed = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $null = Copy-DbaCustomError @splatSeed
            @($destServer.Query("SELECT message_id FROM sys.messages WHERE message_id = 60000")).Count | Should -Be 2

            $splatForce = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CustomError   = 60000
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $forceResults = @(Copy-DbaCustomError @splatForce | Where-Object { $null -ne $PSItem })
            $forceResults.Count | Should -Be 2
            $forceResults.Status | Should -Be @("Failed", "Failed")
            $forceResults[0].Notes | Should -Match "Drop failed"

            @($destServer.Query("SELECT message_id FROM sys.messages WHERE message_id = 60000")).Count | Should -Be 0
        }

        It "Should verify custom error exists" {
            $errorResults = Get-DbaCustomError -SqlInstance $TestConfig.InstanceCopy1
            $errorResults.ID | Should -Contain 60000
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
            $probePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$(Get-Random).ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaCustomError -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Copy-DbaCustomError -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            Set-Content -Path $probePath -Value $probeBody -Encoding UTF8

            $probeOutput = & $shellPath -NoProfile -NonInteractive -File $probePath 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            Remove-Item -Path $probePath -ErrorAction SilentlyContinue
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
}
