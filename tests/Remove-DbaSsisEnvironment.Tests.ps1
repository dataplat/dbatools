#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSsisEnvironment",
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
            { Remove-DbaSsisEnvironment -Environment "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses an instance with no environment named, without reaching the server" {
            # The instance here is unreachable, so a command that had lost the guard would fail
            # with a connection error instead - which is how this leg tells "refused" from "tried
            # and could not", and so proves no catalog.delete_environment call was ever issued.
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                EnableException = $true
            }
            { Remove-DbaSsisEnvironment @splatNoTarget } | Should -Throw "*You must supply -Environment, or pipe in environments from Get-DbaSsisEnvironment*"
        }

        It "Refuses a folder with no environment named, without reaching the server" {
            # -Folder is not a target. A folder with no environment named still means every
            # environment in it, so the guard is on -Environment specifically.
            $splatFolderOnly = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                Folder          = "anything"
                EnableException = $true
            }
            { Remove-DbaSsisEnvironment @splatFolderOnly } | Should -Throw "*You must supply -Environment*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance     = $TestConfig.InstanceSsis
        $primaryFolder    = "dbatoolsci_rmenvfolder1"
        $secondFolder     = "dbatoolsci_rmenvfolder2"
        $targetEnv        = "dbatoolsci_rmenvtarget"
        $whatIfEnv        = "dbatoolsci_rmenvwhatif"
        $guardEnv         = "dbatoolsci_rmenvguard"
        $pipeEnvA         = "dbatoolsci_rmenvpipea"
        $pipeEnvB         = "dbatoolsci_rmenvpipeb"
        $sharedEnv        = "dbatoolsci_rmenvshared"
        $twinEnv          = "dbatoolsci_rmenvtwin"
        $prefixEnv        = "dbatoolsci_rmenvpre"
        $prefixSibling    = "dbatoolsci_rmenvpre_extra"
        $primaryEnvironments = @($targetEnv, $whatIfEnv, $guardEnv, $pipeEnvA, $pipeEnvB, $sharedEnv, $twinEnv, $prefixEnv, $prefixSibling)
        $secondEnvironments = @($sharedEnv, $twinEnv)

        function Get-SsisEnvironmentRow {
            param($Folder, $Environment)
            $splatEnvironmentRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT e.environment_id, e.name FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment"
                SqlParameter = @{
                    folder      = $Folder
                    environment = $Environment
                }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatEnvironmentRead)
        }

        function Get-SsisVariableRow {
            param($Folder, $Environment)
            $splatVariableRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT v.name FROM [catalog].[environment_variables] v JOIN [catalog].[environments] e ON e.environment_id = v.environment_id JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment"
                SqlParameter = @{
                    folder      = $Folder
                    environment = $Environment
                }
            }
            , @(Invoke-DbaQuery @splatVariableRead)
        }

        function Remove-SsisFolderFixture {
            param($FolderName)
            # A folder will not drop while it still holds environments, so a cleanup that only
            # drops the folder leaks both.
            $splatEnvironmentDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "DECLARE @name sysname; DECLARE leftovers CURSOR LOCAL FAST_FORWARD FOR SELECT e.name FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder; OPEN leftovers; FETCH NEXT FROM leftovers INTO @name; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @name; FETCH NEXT FROM leftovers INTO @name; END; CLOSE leftovers; DEALLOCATE leftovers;"
                SqlParameter    = @{ folder = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatEnvironmentDrop

            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
                SqlParameter    = @{ folder = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        # A leftover from an interrupted run would leave the ambiguity leg matching three folders
        # instead of two.
        Remove-SsisFolderFixture -FolderName $primaryFolder
        Remove-SsisFolderFixture -FolderName $secondFolder

        foreach ($fixtureFolder in @($primaryFolder, $secondFolder)) {
            $splatNewFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $fixtureFolder
                Description = "remove environment fixture"
            }
            $null = New-DbaSsisFolder @splatNewFolder
        }

        foreach ($creation in @(@($primaryFolder, $primaryEnvironments), @($secondFolder, $secondEnvironments))) {
            $splatNewEnvironment = @{
                SqlInstance = $ssisInstance
                Folder      = $creation[0]
                Environment = $creation[1]
                Description = "remove environment fixture"
            }
            $null = New-DbaSsisEnvironment @splatNewEnvironment
        }

        # catalog.delete_environment takes the whole variable bag with it, and that cascade is only
        # provable against an environment that actually holds variables. The -WhatIf leg reads the
        # same two variables back, so it also proves -WhatIf spared the contents and not just the
        # environment row.
        foreach ($variableHost in @($targetEnv, $whatIfEnv)) {
            $splatNewVariable = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $variableHost
                Variable    = @("dbatoolsci_rmenvvar1", "dbatoolsci_rmenvvar2")
                DataType    = "String"
                Value       = "fixture"
            }
            $null = New-DbaSsisEnvironmentVariable @splatNewVariable
        }

        # Every later assertion of the form "it is still there" is worthless if the fixture never
        # landed, so the run refuses to start rather than proving nothing quietly.
        foreach ($creation in @(@($primaryFolder, $primaryEnvironments), @($secondFolder, $secondEnvironments))) {
            foreach ($environmentName in $creation[1]) {
                if ((Get-SsisEnvironmentRow -Folder $creation[0] -Environment $environmentName).Count -ne 1) {
                    throw "Fixture environment $environmentName was not created in $($creation[0]) on $ssisInstance - the suite cannot prove a removal against a catalog that never held it."
                }
            }
        }
        if ((Get-SsisVariableRow -Folder $primaryFolder -Environment $targetEnv).Count -ne 2) {
            throw "Fixture variables were not created in $targetEnv on $ssisInstance - the cascade leg would pass against an environment that was empty all along."
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        # Folder literals rather than the variables so cleanup still runs when BeforeAll died
        # before setting them.
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmenvfolder1"
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmenvfolder2"
    }

    Context "Removing an environment" {
        It "Removes the environment and its variables, and reports it in the read command's shape" {
            $read = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $primaryFolder -Environment $targetEnv)[0]
            $splatRemove = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $targetEnv
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironment @splatRemove)
            $removed.Count | Should -Be 1
            $removed[0].Name | Should -Be $targetEnv
            $removed[0].FolderName | Should -Be $primaryFolder
            $removed[0].Status | Should -Be "Dropped"
            $removed[0].EnvironmentId | Should -Be $read.EnvironmentId
            $removed[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisEnvironment"
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $targetEnv).Count | Should -Be 0
            # The proc takes the variables with the environment - it does not refuse a non-empty
            # one the way catalog.delete_folder does.
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $targetEnv).Count | Should -Be 0
        }

        It "Reports an environment that is not there and removes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                Environment     = "dbatoolsci_rmenvabsent"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironment @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Leaves an environment whose name merely starts with the requested one" {
            $splatPrefix = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $prefixEnv
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironment @splatPrefix)
            $removed.Count | Should -Be 1
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $prefixEnv).Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $prefixSibling).Count | Should -Be 1
        }
    }

    Context "The target guard" {
        It "Refuses an instance and a folder with no environment named, and issues no delete" {
            # -Folder with no environment reads as "every environment in that folder". The
            # assertion that matters is not the message but the catalog afterwards: the folder's
            # environments are all still there, so no catalog.delete_environment call was made.
            $before = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $primaryFolder).Name
            $before.Count | Should -BeGreaterThan 0
            $splatNoTarget = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                EnableException = $false
                WarningVariable = "guardWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironment @splatNoTarget)
            $none.Count | Should -Be 0
            ($guardWarnings -join " ") | Should -BeLike "*You must supply -Environment*"
            $after = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $primaryFolder).Name
            Compare-Object -ReferenceObject $before -DifferenceObject $after | Should -BeNullOrEmpty
            $after | Should -Contain $guardEnv
        }
    }

    Context "-WhatIf" {
        It "Reports without removing the environment or emptying it" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $whatIfEnv
                WhatIf      = $true
            }
            $whatIfResult = @(Remove-DbaSsisEnvironment @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $whatIfEnv).Count | Should -Be 1
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $whatIfEnv).Count | Should -Be 2
        }
    }

    Context "An environment name that lives in more than one folder" {
        It "Names the folders and removes none of them" {
            # Environment names are unique only within a folder. Picking one would be a guess and
            # removing both would be a far bigger operation than the caller asked for, so the
            # surviving row in each folder is the assertion, not the message.
            $splatAmbiguous = @{
                SqlInstance     = $ssisInstance
                Environment     = $sharedEnv
                EnableException = $false
                WarningVariable = "ambiguousWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironment @splatAmbiguous)
            $none.Count | Should -Be 0
            ($ambiguousWarnings -join " ") | Should -BeLike "*exists in more than one folder*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$primaryFolder*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$secondFolder*"
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $sharedEnv).Count | Should -Be 1
            (Get-SsisEnvironmentRow -Folder $secondFolder -Environment $sharedEnv).Count | Should -Be 1
        }

        It "Throws the same refusal under -EnableException" {
            $splatAmbiguousThrow = @{
                SqlInstance     = $ssisInstance
                Environment     = $sharedEnv
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisEnvironment @splatAmbiguousThrow } | Should -Throw "*exists in more than one folder*"
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $sharedEnv).Count | Should -Be 1
        }

        It "Removes only the copy in the folder that was named" {
            # Same ambiguous name, disambiguated: the twin in the other folder is what proves
            # -Folder scoped the removal rather than the command picking the first match.
            $splatScoped = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $twinEnv
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironment @splatScoped)
            $removed.Count | Should -Be 1
            $removed[0].FolderName | Should -Be $primaryFolder
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $twinEnv).Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $secondFolder -Environment $twinEnv).Count | Should -Be 1
        }
    }

    Context "Two records in one pipeline" {
        It "Removes the second piped environment as well as the first" {
            # Removal streams per record, so what record 2 does is decided entirely on the second
            # record - record 1 alone proves none of it.
            $firstObject = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $primaryFolder -Environment $pipeEnvA)[0]
            $secondObject = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $primaryFolder -Environment $pipeEnvB)[0]
            $removed = @($firstObject, $secondObject | Remove-DbaSsisEnvironment -Confirm:$false)
            $removed.Count | Should -Be 2
            $removed.Name | Should -Contain $pipeEnvA
            $removed.Name | Should -Contain $pipeEnvB
            @($removed | Where-Object Status -NE "Dropped").Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $pipeEnvA).Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $pipeEnvB).Count | Should -Be 0
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not a catalog environment" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                FolderName  = $primaryFolder
                Name        = $guardEnv
            }
            $splatImposter = @{
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $refused = @($imposter | Remove-DbaSsisEnvironment @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisEnvironment*"
            (Get-SsisEnvironmentRow -Folder $primaryFolder -Environment $guardEnv).Count | Should -Be 1
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Environment     = $guardEnv
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironment @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Environment     = $guardEnv
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisEnvironment @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
