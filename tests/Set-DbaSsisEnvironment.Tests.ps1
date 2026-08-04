#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSsisEnvironment",
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
                "Folder",
                "Environment",
                "Description",
                "NewName",
                "MoveToFolder",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should alias Environment to Name" {
            (Get-Command $CommandName).Parameters["Environment"].Aliases | Should -Contain "Name"
        }

        It "Should keep SqlInstance off the pipeline and out of mandatory" {
            # Both halves are load-bearing where -InputObject also takes pipeline input. Mandatory
            # makes the -InputObject path unbindable outright, and a second ValueFromPipeline
            # parameter double-binds, so an ordinary instance pipeline lands in -InputObject.
            $sqlInstance = (Get-Command $CommandName).Parameters["SqlInstance"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $sqlInstance.Mandatory | Should -BeFalse
            $sqlInstance.ValueFromPipeline | Should -BeFalse
            $inputObject = (Get-Command $CommandName).Parameters["InputObject"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $inputObject.ValueFromPipeline | Should -BeTrue
        }
    }

    Context "Refusals that settle before anything connects" {
        BeforeAll {
            $unreachableInstance = "dbatoolsci_nosuchhost_ssisenvironment"
        }

        It "Refuses a call that changes nothing" {
            $splatNoChange = @{
                SqlInstance     = $unreachableInstance
                Folder          = "anything"
                Environment     = "anything"
                EnableException = $true
            }
            { Set-DbaSsisEnvironment @splatNoChange } | Should -Throw "*You must supply -Description, -NewName or -MoveToFolder*"
        }

        It "Refuses a call with no instance and no input object" {
            { Set-DbaSsisEnvironment -Description "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses -SqlInstance with neither folder nor environment named" {
            # Without a selector the selection would be every environment in the catalog.
            $splatNoSelector = @{
                SqlInstance     = $unreachableInstance
                Description     = "anything"
                EnableException = $true
            }
            { Set-DbaSsisEnvironment @splatNoSelector } | Should -Throw "*You must supply -Folder or -Environment when connecting with -SqlInstance*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        $homeFolder = "dbatoolsci_setenvfolder1"
        $awayFolder = "dbatoolsci_setenvfolder2"

        $describedEnvironment = "dbatoolsci_setenv_desc"
        $renamedEnvironment = "dbatoolsci_setenv_rename"
        $renamedEnvironmentAfter = "dbatoolsci_setenv_rename_after"
        $movedEnvironment = "dbatoolsci_setenv_move"
        $comboEnvironment = "dbatoolsci_setenv_combo"
        $comboEnvironmentAfter = "dbatoolsci_setenv_combo_after"
        $whatIfEnvironment = "dbatoolsci_setenv_whatif"
        $firstPipedEnvironment = "dbatoolsci_setenv_pipe1"
        $secondPipedEnvironment = "dbatoolsci_setenv_pipe2"
        $namedEnvironment = "dbatoolsci_setenv_named"
        $sharedEnvironment = "dbatoolsci_setenv_shared"

        function Get-SsisEnvironmentRow {
            param($FolderName, $EnvironmentName)
            $splatEnvironmentRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT e.environment_id, f.name AS folder_name, e.name, e.description FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName AND e.name = @environmentName"
                SqlParameter = @{ folderName = $FolderName; environmentName = $EnvironmentName }
            }
            Invoke-DbaQuery @splatEnvironmentRead
        }

        # Renames and moves make the fixture names at teardown unknowable from here, so the folder
        # is emptied by what it actually holds rather than by the list this file created.
        function Remove-SsisFolderFixture {
            param($FolderName)
            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "DECLARE @environmentName sysname; WHILE EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName) BEGIN SELECT TOP 1 @environmentName = e.name FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName; EXEC [catalog].[delete_environment] @folder_name = @folderName, @environment_name = @environmentName; END IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folderName) EXEC [catalog].[delete_folder] @folder_name = @folderName;"
                SqlParameter    = @{ folderName = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        foreach ($fixture in @($homeFolder, $awayFolder)) {
            Remove-SsisFolderFixture -FolderName $fixture
            $splatNewFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $fixture
                Description = "environment set fixture"
            }
            $null = New-DbaSsisFolder @splatNewFolder
        }

        $homeEnvironments = @(
            $describedEnvironment,
            $renamedEnvironment,
            $movedEnvironment,
            $comboEnvironment,
            $whatIfEnvironment,
            $firstPipedEnvironment,
            $secondPipedEnvironment,
            $namedEnvironment,
            $sharedEnvironment
        )
        $splatHomeEnvironments = @{
            SqlInstance = $ssisInstance
            Folder      = $homeFolder
            Environment = $homeEnvironments
            Description = "fixture as created"
        }
        $null = New-DbaSsisEnvironment @splatHomeEnvironments

        # The same environment name in a second folder: environment names are only unique within a
        # folder, so this is what proves the folder half of the addressing is carried through.
        $splatAwayEnvironment = @{
            SqlInstance = $ssisInstance
            Folder      = $awayFolder
            Environment = $sharedEnvironment
            Description = "away fixture as created"
        }
        $null = New-DbaSsisEnvironment @splatAwayEnvironment
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($fixture in @($homeFolder, $awayFolder)) {
            Remove-SsisFolderFixture -FolderName $fixture
        }
    }

    Context "-Description" {
        It "Sets the description and returns the environment in the read command's shape" {
            $splatDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $describedEnvironment
                Description = "live connection managers"
            }
            $changed = @(Set-DbaSsisEnvironment @splatDescription)
            $changed.Count | Should -Be 1
            $changed[0].Name | Should -Be $describedEnvironment
            $changed[0].FolderName | Should -Be $homeFolder
            $changed[0].Description | Should -Be "live connection managers"
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $describedEnvironment).description | Should -Be "live connection managers"

            $splatRead = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $describedEnvironment
            }
            $read = @(Get-DbaSsisEnvironment @splatRead)[0]
            $changed[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisEnvironment"
            Compare-Object -ReferenceObject $read.PSObject.Properties.Name -DifferenceObject $changed[0].PSObject.Properties.Name | Should -BeNullOrEmpty
        }

        It "Clears the description when given an empty string" {
            # An empty -Description is a value, not an omission. A command testing the string for
            # emptiness instead of testing bound-parameter presence leaves the old text in place
            # and reports success, which is the trap this leg exists for.
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $describedEnvironment).description | Should -Not -BeNullOrEmpty
            $splatClearDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $describedEnvironment
                Description = ""
            }
            $cleared = @(Set-DbaSsisEnvironment @splatClearDescription)
            $cleared.Count | Should -Be 1
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $describedEnvironment).description | Should -Be ""
        }

        It "Leaves the same name in another folder alone" {
            # Environment names repeat across folders, so a command that resolves on the name alone
            # would change both copies here and still report exactly one object per selection.
            $splatShared = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $sharedEnvironment
                Description = "home copy only"
            }
            $changed = @(Set-DbaSsisEnvironment @splatShared)
            $changed.Count | Should -Be 1
            $changed[0].FolderName | Should -Be $homeFolder
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $sharedEnvironment).description | Should -Be "home copy only"
            (Get-SsisEnvironmentRow -FolderName $awayFolder -EnvironmentName $sharedEnvironment).description | Should -Be "away fixture as created"
        }

        It "Reports an environment that is not there and changes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = $homeFolder
                Environment     = "dbatoolsci_setenv_absent"
                Description     = "should not land"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisEnvironment @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Reports without changing anything under -WhatIf" {
            $before = (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $whatIfEnvironment).description
            $splatWhatIfDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $whatIfEnvironment
                Description = "not applied"
                WhatIf      = $true
            }
            $whatIfResult = @(Set-DbaSsisEnvironment @splatWhatIfDescription)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $whatIfEnvironment).description | Should -Be $before
        }
    }

    Context "-NewName" {
        It "Renames an environment piped in from the read command" {
            $splatReadRename = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $renamedEnvironment
            }
            $renamed = @(Get-DbaSsisEnvironment @splatReadRename | Set-DbaSsisEnvironment -NewName $renamedEnvironmentAfter)
            $renamed.Count | Should -Be 1
            $renamed[0].Name | Should -Be $renamedEnvironmentAfter
            $renamed[0].FolderName | Should -Be $homeFolder
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $renamedEnvironmentAfter).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $renamedEnvironment).Count | Should -Be 0
        }

        It "Leaves the description alone when only the name changes" {
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $renamedEnvironmentAfter).description | Should -Be "fixture as created"
        }

        It "Refuses to rename a selection of more than one environment and changes neither" {
            # The count that decides this is the count across the whole pipeline, so a per-record
            # check would have renamed the first environment before the second arrived to refuse
            # it. Two objects are piped literally rather than through a name list, so the leg
            # cannot quietly become a one-record leg if a fixture goes missing.
            $splatReadFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $firstPipedEnvironment
            }
            $splatReadSecond = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $secondPipedEnvironment
            }
            $firstObject = @(Get-DbaSsisEnvironment @splatReadFirst)[0]
            $secondObject = @(Get-DbaSsisEnvironment @splatReadSecond)[0]
            $splatBoth = @{
                NewName         = "dbatoolsci_setenv_collapsed"
                EnableException = $false
                WarningVariable = "collapseWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($firstObject, $secondObject | Set-DbaSsisEnvironment @splatBoth)
            $refused.Count | Should -Be 0
            ($collapseWarnings -join " ") | Should -BeLike "*-NewName renames one environment*"
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $firstPipedEnvironment).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $secondPipedEnvironment).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName "dbatoolsci_setenv_collapsed").Count | Should -Be 0
        }
    }

    Context "-MoveToFolder" {
        It "Moves an environment into another folder and reports it there" {
            $splatMove = @{
                SqlInstance  = $ssisInstance
                Folder       = $homeFolder
                Environment  = $movedEnvironment
                MoveToFolder = $awayFolder
            }
            $moved = @(Set-DbaSsisEnvironment @splatMove)
            $moved.Count | Should -Be 1
            $moved[0].Name | Should -Be $movedEnvironment
            $moved[0].FolderName | Should -Be $awayFolder
            @(Get-SsisEnvironmentRow -FolderName $awayFolder -EnvironmentName $movedEnvironment).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $movedEnvironment).Count | Should -Be 0
        }

        It "Reports without moving anything under -WhatIf" {
            $splatWhatIfMove = @{
                SqlInstance  = $ssisInstance
                Folder       = $homeFolder
                Environment  = $whatIfEnvironment
                MoveToFolder = $awayFolder
                WhatIf       = $true
            }
            $whatIfResult = @(Set-DbaSsisEnvironment @splatWhatIfMove)
            $whatIfResult.Count | Should -Be 0
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $whatIfEnvironment).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $awayFolder -EnvironmentName $whatIfEnvironment).Count | Should -Be 0
        }

        It "Refuses to move a selection of more than one environment and moves neither" {
            $splatReadFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $firstPipedEnvironment
            }
            $splatReadSecond = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $secondPipedEnvironment
            }
            $firstObject = @(Get-DbaSsisEnvironment @splatReadFirst)[0]
            $secondObject = @(Get-DbaSsisEnvironment @splatReadSecond)[0]
            $splatBothMove = @{
                MoveToFolder    = $awayFolder
                EnableException = $false
                WarningVariable = "moveWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($firstObject, $secondObject | Set-DbaSsisEnvironment @splatBothMove)
            $refused.Count | Should -Be 0
            ($moveWarnings -join " ") | Should -BeLike "*-MoveToFolder moves one environment*"
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $firstPipedEnvironment).Count | Should -Be 1
            @(Get-SsisEnvironmentRow -FolderName $awayFolder -EnvironmentName $secondPipedEnvironment).Count | Should -Be 0
        }
    }

    Context "All three changes in one call" {
        It "Describes, renames, then moves - and reports the final name in the final folder" {
            # Order is the whole leg. The description and the rename address the environment where
            # it was resolved, so a move taken first invalidates the folder name they were bound
            # to and the catalog rejects them for an environment that is no longer there.
            $splatCombo = @{
                SqlInstance  = $ssisInstance
                Folder       = $homeFolder
                Environment  = $comboEnvironment
                Description  = "described renamed and moved"
                NewName      = $comboEnvironmentAfter
                MoveToFolder = $awayFolder
            }
            $changed = @(Set-DbaSsisEnvironment @splatCombo)
            $changed.Count | Should -Be 1
            $changed[0].Name | Should -Be $comboEnvironmentAfter
            $changed[0].FolderName | Should -Be $awayFolder
            $changed[0].Description | Should -Be "described renamed and moved"

            $landed = Get-SsisEnvironmentRow -FolderName $awayFolder -EnvironmentName $comboEnvironmentAfter
            @($landed).Count | Should -Be 1
            $landed.description | Should -Be "described renamed and moved"
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $comboEnvironment).Count | Should -Be 0
            @(Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $comboEnvironmentAfter).Count | Should -Be 0
        }
    }

    Context "Two records in one pipeline" {
        It "Changes the second piped environment as well as the first" {
            # A description change streams per record, so what record 2 does is decided entirely
            # on the second record - record 1 alone proves none of it.
            $splatReadFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $firstPipedEnvironment
            }
            $splatReadSecond = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $secondPipedEnvironment
            }
            $firstObject = @(Get-DbaSsisEnvironment @splatReadFirst)[0]
            $secondObject = @(Get-DbaSsisEnvironment @splatReadSecond)[0]
            $changed = @($firstObject, $secondObject | Set-DbaSsisEnvironment -Description "piped in a batch")
            $changed.Count | Should -Be 2
            $changed.Name | Should -Contain $firstPipedEnvironment
            $changed.Name | Should -Contain $secondPipedEnvironment
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $firstPipedEnvironment).description | Should -Be "piped in a batch"
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $secondPipedEnvironment).description | Should -Be "piped in a batch"
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not a catalog environment" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                FolderName  = $homeFolder
                Name        = $firstPipedEnvironment
            }
            $splatImposter = @{
                Description     = "should not land"
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($imposter | Set-DbaSsisEnvironment @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisEnvironment*"
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $firstPipedEnvironment).description | Should -Be "piped in a batch"
        }
    }

    Context "-SqlInstance named while records are also piped in" {
        It "Acts on the named environment once, not once per piped record" {
            # -SqlInstance is not pipeline-bound: it is supplied once no matter how many records
            # arrive, so the environments it names are one selection, not one per record. Expanded
            # on every record instead, the named environment is updated and emitted as many times
            # as records were piped - which reads as success and quietly does the work twice.
            $splatReadFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $firstPipedEnvironment
            }
            $splatReadSecond = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $secondPipedEnvironment
            }
            $firstPiped = @(Get-DbaSsisEnvironment @splatReadFirst)[0]
            $secondPiped = @(Get-DbaSsisEnvironment @splatReadSecond)[0]
            $splatMixed = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $namedEnvironment
                Description = "named and piped together"
            }
            $mixed = @($firstPiped, $secondPiped | Set-DbaSsisEnvironment @splatMixed)

            $mixed.Count | Should -Be 3
            @($mixed | Where-Object Name -EQ $namedEnvironment).Count | Should -Be 1
            foreach ($touched in @($firstPipedEnvironment, $secondPipedEnvironment, $namedEnvironment)) {
                (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $touched).description | Should -Be "named and piped together"
            }
        }

        It "Counts the named environment once when it refuses a rename of several" {
            # The count in the refusal is the selection the command actually built, so it is the
            # one place the duplication shows even though both a right and a wrong count refuse.
            $splatReadFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $firstPipedEnvironment
            }
            $splatReadSecond = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $secondPipedEnvironment
            }
            $firstPiped = @(Get-DbaSsisEnvironment @splatReadFirst)[0]
            $secondPiped = @(Get-DbaSsisEnvironment @splatReadSecond)[0]
            $splatMixedRename = @{
                SqlInstance = $ssisInstance
                Folder      = $homeFolder
                Environment = $namedEnvironment
                NewName     = "dbatoolsci_setenv_neverapplied"
            }
            $refused = $null
            try {
                $firstPiped, $secondPiped | Set-DbaSsisEnvironment @splatMixedRename
            } catch {
                $refused = $PSItem
            }
            $refused | Should -Not -BeNullOrEmpty
            $refused.Exception.Message | Should -BeLike "*resolved to 3 (*"
            Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName "dbatoolsci_setenv_neverapplied" | Should -BeNullOrEmpty
            (Get-SsisEnvironmentRow -FolderName $homeFolder -EnvironmentName $namedEnvironment).name | Should -Be $namedEnvironment
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $homeFolder
                Environment     = $namedEnvironment
                Description     = "no catalog here"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisEnvironment @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }
    }
}
