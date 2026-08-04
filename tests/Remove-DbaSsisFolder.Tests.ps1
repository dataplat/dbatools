#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSsisFolder",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess at High impact" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
            $cmdletBinding = (Get-Command $CommandName).ImplementingType.GetCustomAttributes([System.Management.Automation.CmdletAttribute], $false)[0]
            $cmdletBinding.SupportsShouldProcess | Should -BeTrue
            $cmdletBinding.ConfirmImpact | Should -Be "High"
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
        It "Refuses a call with no instance and no input object" {
            { Remove-DbaSsisFolder -Folder "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses an instance with no folder named, without reaching the server" {
            # -SqlInstance alone means every folder in the catalog. The instance here is
            # unreachable, so a command that had lost the guard would fail with a connection
            # error instead - which is how this leg tells "refused" from "tried and could not".
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                EnableException = $true
            }
            { Remove-DbaSsisFolder @splatNoTarget } | Should -Throw "*You must supply -Folder, or pipe in folders from Get-DbaSsisFolder*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        $emptyFolder = "dbatoolsci_remfolder_empty"
        $pipeFolderA = "dbatoolsci_remfolder_pipea"
        $pipeFolderB = "dbatoolsci_remfolder_pipeb"
        $guardFolder = "dbatoolsci_remfolder_guard"
        $whatIfFolder = "dbatoolsci_remfolder_whatif"
        $prefixFolder = "dbatoolsci_remfolder_pre"
        $prefixSibling = "dbatoolsci_remfolder_pre_extra"
        $fullFolder = "dbatoolsci_remfolder_full"
        $namedFolder = "dbatoolsci_remfolder_named"
        $fullEnvironment = "dbatoolsci_remfolder_env"
        $allFixtures = @($emptyFolder, $pipeFolderA, $pipeFolderB, $guardFolder, $whatIfFolder, $prefixFolder, $prefixSibling, $fullFolder, $namedFolder)

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
            # Environments have to go before the folder will: delete_folder refuses a folder that
            # still holds objects, so a cleanup that only drops the folder leaks both.
            $splatEnvironmentDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "DECLARE @environment sysname; DECLARE environments CURSOR LOCAL FAST_FORWARD FOR SELECT e.name FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folderName; OPEN environments; FETCH NEXT FROM environments INTO @environment; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_environment] @folder_name = @folderName, @environment_name = @environment; FETCH NEXT FROM environments INTO @environment; END; CLOSE environments; DEALLOCATE environments;"
                SqlParameter    = @{ folderName = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatEnvironmentDrop

            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folderName) EXEC [catalog].[delete_folder] @folder_name = @folderName;"
                SqlParameter    = @{ folderName = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        foreach ($fixture in $allFixtures) {
            Remove-SsisFolderFixture -FolderName $fixture
        }

        foreach ($fixture in $allFixtures) {
            $splatNewFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $fixture
                Description = "remove fixture"
            }
            $null = New-DbaSsisFolder @splatNewFolder
        }

        $splatFullEnvironment = @{
            SqlInstance = $ssisInstance
            Folder      = $fullFolder
            Environment = $fullEnvironment
            Description = "keeps the folder occupied"
        }
        $null = New-DbaSsisEnvironment @splatFullEnvironment
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($fixture in $allFixtures) {
            Remove-SsisFolderFixture -FolderName $fixture
        }
    }

    Context "Removing a folder" {
        It "Removes the folder and reports it in the read command's shape" {
            $read = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $emptyFolder)[0]
            $removed = @(Remove-DbaSsisFolder -SqlInstance $ssisInstance -Folder $emptyFolder -Confirm:$false)
            $removed.Count | Should -Be 1
            $removed[0].Name | Should -Be $emptyFolder
            $removed[0].Status | Should -Be "Dropped"
            $removed[0].FolderId | Should -Be $read.FolderId
            $removed[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisFolder"
            @(Get-SsisFolderRow -FolderName $emptyFolder).Count | Should -Be 0
        }

        It "Reports a folder that is not there and removes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = "dbatoolsci_remfolder_absent"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisFolder @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Keeps going past a folder that is not there" {
            # The absent folder is named FIRST, so a command whose per-item failure latched instead
            # of continuing would leave the real folder standing and still look like a clean run.
            $splatMixedNames = @{
                SqlInstance     = $ssisInstance
                Folder          = "dbatoolsci_remfolder_absent", $namedFolder
                EnableException = $false
                WarningVariable = "continueWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $removed = @(Remove-DbaSsisFolder @splatMixedNames)
            $removed.Count | Should -Be 1
            $removed[0].Name | Should -Be $namedFolder
            @(Get-SsisFolderRow -FolderName $namedFolder).Count | Should -Be 0
        }
    }

    Context "The target guard" {
        It "Refuses an instance with no folder named and issues no delete" {
            # -SqlInstance sql01 with no target reads as "every folder in the catalog". The
            # assertion that matters is not the message but the catalog afterwards: every fixture
            # folder is still there, so no catalog.delete_folder call was made.
            $before = @(Get-DbaSsisFolder -SqlInstance $ssisInstance).Name
            $before.Count | Should -BeGreaterThan 0
            $splatNoTarget = @{
                SqlInstance     = $ssisInstance
                EnableException = $false
                WarningVariable = "guardWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisFolder @splatNoTarget)
            $none.Count | Should -Be 0
            ($guardWarnings -join " ") | Should -BeLike "*You must supply -Folder*"
            $after = @(Get-DbaSsisFolder -SqlInstance $ssisInstance).Name
            Compare-Object -ReferenceObject $before -DifferenceObject $after | Should -BeNullOrEmpty
            $after | Should -Contain $guardFolder
        }
    }

    Context "-WhatIf" {
        It "Reports without removing anything" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $whatIfFolder
                WhatIf      = $true
            }
            $whatIfResult = @(Remove-DbaSsisFolder @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            @(Get-SsisFolderRow -FolderName $whatIfFolder).Count | Should -Be 1
        }

        It "Leaves a folder's contents alone as well as the folder" {
            $splatWhatIfFull = @{
                SqlInstance = $ssisInstance
                Folder      = $fullFolder
                WhatIf      = $true
            }
            $null = Remove-DbaSsisFolder @splatWhatIfFull
            @(Get-SsisFolderRow -FolderName $fullFolder).Count | Should -Be 1
            @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $fullFolder -Environment $fullEnvironment).Count | Should -Be 1
        }
    }

    Context "Names are matched exactly" {
        It "Leaves a folder whose name merely starts with the requested one" {
            $splatPrefix = @{
                SqlInstance = $ssisInstance
                Folder      = $prefixFolder
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisFolder @splatPrefix)
            $removed.Count | Should -Be 1
            @(Get-SsisFolderRow -FolderName $prefixFolder).Count | Should -Be 0
            @(Get-SsisFolderRow -FolderName $prefixSibling).Count | Should -Be 1
        }
    }

    Context "A folder that still holds objects" {
        It "Surfaces the catalog's own refusal and leaves the folder standing" {
            # The command does not pre-flight a count: whether a non-empty folder can go is the
            # server's rule. On SQL 2019 (catalog schema 6) delete_folder refuses it, and that
            # error has to reach the caller rather than be swallowed into a quiet no-op.
            $splatFull = @{
                SqlInstance     = $ssisInstance
                Folder          = $fullFolder
                EnableException = $false
                WarningVariable = "fullWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisFolder @splatFull)
            $none.Count | Should -Be 0
            ($fullWarnings -join " ") | Should -BeLike "*Failure removing SSIS folder*"
            ($fullWarnings -join " ") | Should -BeLike "*not empty*"
            @(Get-SsisFolderRow -FolderName $fullFolder).Count | Should -Be 1
            @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $fullFolder -Environment $fullEnvironment).Count | Should -Be 1
        }

        It "Throws the same refusal under -EnableException" {
            $splatFullThrow = @{
                SqlInstance     = $ssisInstance
                Folder          = $fullFolder
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisFolder @splatFullThrow } | Should -Throw "*not empty*"
            @(Get-SsisFolderRow -FolderName $fullFolder).Count | Should -Be 1
        }
    }

    Context "Two records in one pipeline" {
        It "Removes the second piped folder as well as the first" {
            # Removal streams per record, so what record 2 does is decided entirely on the second
            # record - record 1 alone proves none of it.
            $firstObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $pipeFolderA)[0]
            $secondObject = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $pipeFolderB)[0]
            $removed = @($firstObject, $secondObject | Remove-DbaSsisFolder -Confirm:$false)
            $removed.Count | Should -Be 2
            $removed.Name | Should -Contain $pipeFolderA
            $removed.Name | Should -Contain $pipeFolderB
            @($removed | Where-Object Status -NE "Dropped").Count | Should -Be 0
            @(Get-SsisFolderRow -FolderName $pipeFolderA).Count | Should -Be 0
            @(Get-SsisFolderRow -FolderName $pipeFolderB).Count | Should -Be 0
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not a catalog folder" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Name        = $guardFolder
            }
            $splatImposter = @{
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $refused = @($imposter | Remove-DbaSsisFolder @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisFolder*"
            @(Get-SsisFolderRow -FolderName $guardFolder).Count | Should -Be 1
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $guardFolder
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisFolder @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $guardFolder
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisFolder @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
