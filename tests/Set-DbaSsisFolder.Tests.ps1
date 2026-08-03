#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSsisFolder",
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
                "Description",
                "NewName",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
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
            $unreachableInstance = "dbatoolsci_nosuchhost_ssisfolder"
        }

        It "Refuses a call that changes nothing" {
            $splatNoChange = @{
                SqlInstance     = $unreachableInstance
                Folder          = "anything"
                EnableException = $true
            }
            { Set-DbaSsisFolder @splatNoChange } | Should -Throw "*You must supply -Description or -NewName*"
        }

        It "Refuses a call with no instance and no input object" {
            { Set-DbaSsisFolder -Description "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses -SqlInstance with no folder named" {
            # Without it the selection would be every folder in the catalog.
            $splatNoFolder = @{
                SqlInstance     = $unreachableInstance
                Description     = "anything"
                EnableException = $true
            }
            { Set-DbaSsisFolder @splatNoFolder } | Should -Throw "*You must supply -Folder when connecting with -SqlInstance*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        $firstFolder = "dbatoolsci_setfolder1"
        $secondFolder = "dbatoolsci_setfolder2"
        $renamedFolder = "dbatoolsci_setfolder2_renamed"
        $thirdFolder = "dbatoolsci_setfolder3"

        function Get-SsisFolderRow {
            param($FolderName)
            $splatFolderRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT folder_id, name, description FROM [catalog].[folders] WHERE name = @folderName"
                SqlParameter = @{ folderName = $FolderName }
            }
            Invoke-DbaQuery @splatFolderRead
        }

        function Remove-SsisFolderFixture {
            param($FolderName)
            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folderName) EXEC [catalog].[delete_folder] @folder_name = @folderName;"
                SqlParameter    = @{ folderName = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        foreach ($fixture in @($firstFolder, $secondFolder, $renamedFolder, $thirdFolder)) {
            Remove-SsisFolderFixture -FolderName $fixture
        }

        $splatFirstFixture = @{
            SqlInstance = $ssisInstance
            Folder      = $firstFolder
            Description = "first fixture"
        }
        $null = New-DbaSsisFolder @splatFirstFixture
        $splatSecondFixture = @{
            SqlInstance = $ssisInstance
            Folder      = $secondFolder
            Description = "second fixture"
        }
        $null = New-DbaSsisFolder @splatSecondFixture
        $splatThirdFixture = @{
            SqlInstance = $ssisInstance
            Folder      = $thirdFolder
            Description = "third fixture"
        }
        $null = New-DbaSsisFolder @splatThirdFixture
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($fixture in @($firstFolder, $secondFolder, $renamedFolder, $thirdFolder)) {
            Remove-SsisFolderFixture -FolderName $fixture
        }
    }

    Context "-Description" {
        It "Sets the description and returns the folder in the read command's shape" {
            $splatDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $firstFolder
                Description = "nightly finance loads"
            }
            $changed = @(Set-DbaSsisFolder @splatDescription)
            $changed.Count | Should -Be 1
            $changed[0].Name | Should -Be $firstFolder
            $changed[0].Description | Should -Be "nightly finance loads"
            (Get-SsisFolderRow -FolderName $firstFolder).description | Should -Be "nightly finance loads"

            $read = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $firstFolder)[0]
            $changed[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisFolder"
            Compare-Object -ReferenceObject $read.PSObject.Properties.Name -DifferenceObject $changed[0].PSObject.Properties.Name | Should -BeNullOrEmpty
        }

        It "Clears the description when given an empty string" {
            # An empty -Description is a value, not an omission. A command testing the string for
            # emptiness instead of testing bound-parameter presence leaves the old text in place
            # and reports success, which is the trap this leg exists for.
            (Get-SsisFolderRow -FolderName $firstFolder).description | Should -Not -BeNullOrEmpty
            $splatClearDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $firstFolder
                Description = ""
            }
            $cleared = @(Set-DbaSsisFolder @splatClearDescription)
            $cleared.Count | Should -Be 1
            (Get-SsisFolderRow -FolderName $firstFolder).description | Should -Be ""
        }

        It "Reports a folder that is not there and changes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = "dbatoolsci_setfolder_absent"
                Description     = "should not land"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisFolder @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Reports without changing anything under -WhatIf" {
            $before = (Get-SsisFolderRow -FolderName $secondFolder).description
            $splatWhatIfDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $secondFolder
                Description = "not applied"
                WhatIf      = $true
            }
            $whatIfResult = @(Set-DbaSsisFolder @splatWhatIfDescription)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisFolderRow -FolderName $secondFolder).description | Should -Be $before
        }
    }

    Context "-NewName" {
        It "Renames a folder piped in from the read command" {
            $renamed = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $secondFolder | Set-DbaSsisFolder -NewName $renamedFolder)
            $renamed.Count | Should -Be 1
            $renamed[0].Name | Should -Be $renamedFolder
            @(Get-SsisFolderRow -FolderName $renamedFolder).Count | Should -Be 1
            @(Get-SsisFolderRow -FolderName $secondFolder).Count | Should -Be 0
        }

        It "Leaves the description alone when only the name changes" {
            (Get-SsisFolderRow -FolderName $renamedFolder).description | Should -Be "second fixture"
        }

        It "Refuses to rename a selection of more than one folder and changes neither" {
            # The count that decides this is the count across the whole pipeline, so a per-record
            # check would have renamed the first folder before the second arrived to refuse it.
            # Two objects are piped literally rather than through a name list, so the leg cannot
            # quietly become a one-record leg if a fixture goes missing.
            $firstObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $firstFolder)[0]
            $secondObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $renamedFolder)[0]
            $splatBoth = @{
                NewName         = "dbatoolsci_setfolder_collapsed"
                EnableException = $false
                WarningVariable = "collapseWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($firstObject, $secondObject | Set-DbaSsisFolder @splatBoth)
            $refused.Count | Should -Be 0
            ($collapseWarnings -join " ") | Should -BeLike "*-NewName renames one folder*"
            @(Get-SsisFolderRow -FolderName $firstFolder).Count | Should -Be 1
            @(Get-SsisFolderRow -FolderName $renamedFolder).Count | Should -Be 1
            @(Get-SsisFolderRow -FolderName "dbatoolsci_setfolder_collapsed").Count | Should -Be 0
        }
    }

    Context "Two records in one pipeline" {
        It "Changes the second piped folder as well as the first" {
            # A description change streams per record, so what record 2 does is decided entirely
            # on the second record - record 1 alone proves none of it.
            $firstObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $firstFolder)[0]
            $secondObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $renamedFolder)[0]
            $changed = @($firstObject, $secondObject | Set-DbaSsisFolder -Description "piped in a batch")
            $changed.Count | Should -Be 2
            $changed.Name | Should -Contain $firstFolder
            $changed.Name | Should -Contain $renamedFolder
            (Get-SsisFolderRow -FolderName $firstFolder).description | Should -Be "piped in a batch"
            (Get-SsisFolderRow -FolderName $renamedFolder).description | Should -Be "piped in a batch"
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not a catalog folder" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Name        = $firstFolder
            }
            $splatImposter = @{
                Description     = "should not land"
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($imposter | Set-DbaSsisFolder @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisFolder*"
            (Get-SsisFolderRow -FolderName $firstFolder).description | Should -Be "piped in a batch"
        }
    }

    Context "-SqlInstance named while records are also piped in" {
        It "Acts on the named folder once, not once per piped record" {
            # -SqlInstance is not pipeline-bound: it is supplied once no matter how many records
            # arrive, so the folders it names are one selection, not one per record. Expanded on
            # every record instead, the named folder is updated and emitted as many times as
            # records were piped - which reads as success and quietly does the work twice.
            $firstPiped = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $firstFolder)[0]
            $secondPiped = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $renamedFolder)[0]
            $splatMixed = @{
                SqlInstance = $ssisInstance
                Folder      = $thirdFolder
                Description = "named and piped together"
            }
            $mixed = @($firstPiped, $secondPiped | Set-DbaSsisFolder @splatMixed)

            $mixed.Count | Should -Be 3
            @($mixed | Where-Object Name -EQ $thirdFolder).Count | Should -Be 1
            foreach ($touched in @($firstFolder, $renamedFolder, $thirdFolder)) {
                (Get-SsisFolderRow -FolderName $touched).description | Should -Be "named and piped together"
            }
        }

        It "Counts the named folder once when it refuses a rename of several" {
            # The count in the refusal is the selection the command actually built, so it is the
            # one place the duplication shows even though both a right and a wrong count refuse.
            $firstPiped = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $firstFolder)[0]
            $secondPiped = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $renamedFolder)[0]
            $splatMixedRename = @{
                SqlInstance = $ssisInstance
                Folder      = $thirdFolder
                NewName     = "dbatoolsci_setfolder_neverapplied"
            }
            $refused = $null
            try {
                $firstPiped, $secondPiped | Set-DbaSsisFolder @splatMixedRename
            } catch {
                $refused = $PSItem
            }
            $refused | Should -Not -BeNullOrEmpty
            $refused.Exception.Message | Should -BeLike "*resolved to 3 (*"
            (Get-SsisFolderRow -FolderName "dbatoolsci_setfolder_neverapplied") | Should -BeNullOrEmpty
            (Get-SsisFolderRow -FolderName $thirdFolder).name | Should -Be $thirdFolder
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $firstFolder
                Description     = "no catalog here"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisFolder @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }
    }
}
