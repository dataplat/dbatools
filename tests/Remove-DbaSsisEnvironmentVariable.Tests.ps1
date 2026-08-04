#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSsisEnvironmentVariable",
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
                "Variable",
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
            { Remove-DbaSsisEnvironmentVariable -Variable "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses an instance with no variable named, without reaching the server" {
            # The instance here is unreachable, so a command that had lost the guard would fail
            # with a connection error instead - which is how this leg tells "refused" from "tried
            # and could not", and so proves no catalog.delete_environment_variable call was issued.
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                EnableException = $true
            }
            { Remove-DbaSsisEnvironmentVariable @splatNoTarget } | Should -Throw "*You must supply -Variable, or pipe in variables from Get-DbaSsisEnvironmentVariable*"
        }

        It "Refuses a folder and an environment with no variable named, without reaching the server" {
            # -Environment is not a target. An environment with no variable named still means every
            # variable in it, which empties the environment, so the guard is on -Variable.
            $splatEnvironmentOnly = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                Folder          = "anything"
                Environment     = "anything"
                EnableException = $true
            }
            { Remove-DbaSsisEnvironmentVariable @splatEnvironmentOnly } | Should -Throw "*You must supply -Variable*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance    = $TestConfig.InstanceSsis
        $primaryFolder   = "dbatoolsci_rmvarfolder1"
        $secondFolder    = "dbatoolsci_rmvarfolder2"
        $primaryEnv      = "dbatoolsci_rmvarenv1"
        $secondEnv       = "dbatoolsci_rmvarenv2"
        $targetVariable  = "dbatoolsci_rmvartarget"
        $keeperVariable  = "dbatoolsci_rmvarkeeper"
        $whatIfVariable  = "dbatoolsci_rmvarwhatif"
        $guardVariableA  = "dbatoolsci_rmvarguarda"
        $guardVariableB  = "dbatoolsci_rmvarguardb"
        $sensitiveVar    = "dbatoolsci_rmvarsecret"
        $sharedVariable  = "dbatoolsci_rmvarshared"
        $twinVariable    = "dbatoolsci_rmvartwin"
        $prefixVariable  = "dbatoolsci_rmvarpre"
        $prefixSibling   = "dbatoolsci_rmvarpre_extra"
        $pipeVariableA   = "dbatoolsci_rmvarpipea"
        $pipeVariableB   = "dbatoolsci_rmvarpipeb"
        $primaryVariables = @($targetVariable, $keeperVariable, $whatIfVariable, $guardVariableA, $guardVariableB, $sharedVariable, $twinVariable, $prefixVariable, $prefixSibling)
        $secondVariables = @($sharedVariable, $twinVariable)

        function Get-SsisVariableRow {
            param($Folder, $Environment, $Variable)
            $splatVariableRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT v.name, v.sensitive FROM [catalog].[environment_variables] v JOIN [catalog].[environments] e ON e.environment_id = v.environment_id JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment AND v.name = @variable"
                SqlParameter = @{
                    folder      = $Folder
                    environment = $Environment
                    variable    = $Variable
                }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatVariableRead)
        }

        function Get-SsisVariableNameList {
            param($Folder, $Environment)
            $splatNameList = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT v.name FROM [catalog].[environment_variables] v JOIN [catalog].[environments] e ON e.environment_id = v.environment_id JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment ORDER BY v.name"
                SqlParameter = @{
                    folder      = $Folder
                    environment = $Environment
                }
            }
            , @((Invoke-DbaQuery @splatNameList).name)
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

        # A leftover from an interrupted run would leave the ambiguity leg matching three
        # environments instead of two.
        Remove-SsisFolderFixture -FolderName $primaryFolder
        Remove-SsisFolderFixture -FolderName $secondFolder

        foreach ($creation in @(@($primaryFolder, $primaryEnv), @($secondFolder, $secondEnv))) {
            $splatNewFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $creation[0]
                Description = "remove environment variable fixture"
            }
            $null = New-DbaSsisFolder @splatNewFolder

            $splatNewEnvironment = @{
                SqlInstance = $ssisInstance
                Folder      = $creation[0]
                Environment = $creation[1]
                Description = "remove environment variable fixture"
            }
            $null = New-DbaSsisEnvironment @splatNewEnvironment
        }

        foreach ($population in @(@($primaryFolder, $primaryEnv, $primaryVariables), @($secondFolder, $secondEnv, $secondVariables))) {
            $splatNewVariable = @{
                SqlInstance = $ssisInstance
                Folder      = $population[0]
                Environment = $population[1]
                Variable    = $population[2]
                DataType    = "String"
                Value       = "fixture"
            }
            $null = New-DbaSsisEnvironmentVariable @splatNewVariable
        }

        # A sensitive variable is the one case where the removed value cannot be recovered, so the
        # emitted object is asserted to carry no plaintext for it.
        $splatSensitive = @{
            SqlInstance = $ssisInstance
            Folder      = $primaryFolder
            Environment = $primaryEnv
            Variable    = $sensitiveVar
            DataType    = "String"
            SecureValue = (ConvertTo-SecureString -String "dbatoolsci_secret" -AsPlainText -Force)
            Sensitive   = $true
        }
        $null = New-DbaSsisEnvironmentVariable @splatSensitive

        # Every later assertion of the form "it is still there" is worthless if the fixture never
        # landed, so the run refuses to start rather than proving nothing quietly.
        foreach ($population in @(@($primaryFolder, $primaryEnv, $primaryVariables), @($secondFolder, $secondEnv, $secondVariables))) {
            foreach ($variableName in $population[2]) {
                if ((Get-SsisVariableRow -Folder $population[0] -Environment $population[1] -Variable $variableName).Count -ne 1) {
                    throw "Fixture variable $variableName was not created in $($population[0])\$($population[1]) on $ssisInstance - the suite cannot prove a removal against an environment that never held it."
                }
            }
        }
        if ((Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $sensitiveVar)[0].sensitive -ne $true) {
            throw "Fixture variable $sensitiveVar is not stored sensitive on $ssisInstance - the no-plaintext leg would pass against an ordinary variable."
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        # Folder literals rather than the variables so cleanup still runs when BeforeAll died
        # before setting them.
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmvarfolder1"
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmvarfolder2"
    }

    Context "Removing a variable" {
        It "Removes the variable and reports it in the read command's shape" {
            $splatRemove = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = $targetVariable
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironmentVariable @splatRemove)
            $removed.Count | Should -Be 1
            $removed[0].Name | Should -Be $targetVariable
            $removed[0].Folder | Should -Be $primaryFolder
            $removed[0].Environment | Should -Be $primaryEnv
            $removed[0].Type | Should -Be "String"
            $removed[0].Status | Should -Be "Dropped"
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $targetVariable).Count | Should -Be 0
            # A single-row delete, not an emptying: the environment keeps everything else.
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $keeperVariable).Count | Should -Be 1
        }

        It "Removes a sensitive variable without echoing its value" {
            $splatSensitiveRemove = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = $sensitiveVar
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironmentVariable @splatSensitiveRemove)
            $removed.Count | Should -Be 1
            $removed[0].IsSensitive | Should -BeTrue
            # The catalog leaves the plain value column null for a sensitive variable and the
            # encrypted column is deliberately never read, so the secret does not ride out on the
            # confirmation object.
            $removed[0].Value | Should -BeNullOrEmpty
            ($removed[0].PSObject.Properties.Name) | Should -Not -Contain "SensitiveValue"
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $sensitiveVar).Count | Should -Be 0
        }

        It "Reports a variable that is not there and removes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                Environment     = $primaryEnv
                Variable        = "dbatoolsci_rmvarabsent"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironmentVariable @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Leaves a variable whose name merely starts with the requested one" {
            $splatPrefix = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = $prefixVariable
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironmentVariable @splatPrefix)
            $removed.Count | Should -Be 1
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $prefixVariable).Count | Should -Be 0
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $prefixSibling).Count | Should -Be 1
        }
    }

    Context "The target guard" {
        It "Refuses an environment with no variable named, and issues no delete" {
            # -Environment with no variable reads as "every variable in that environment", which
            # empties it. The assertion that matters is not the message but the catalog afterwards:
            # the environment's variables are all still there, so no
            # catalog.delete_environment_variable call was made.
            $before = Get-SsisVariableNameList -Folder $primaryFolder -Environment $primaryEnv
            $before.Count | Should -BeGreaterThan 0
            $splatNoTarget = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                Environment     = $primaryEnv
                EnableException = $false
                WarningVariable = "guardWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironmentVariable @splatNoTarget)
            $none.Count | Should -Be 0
            ($guardWarnings -join " ") | Should -BeLike "*You must supply -Variable*"
            $after = Get-SsisVariableNameList -Folder $primaryFolder -Environment $primaryEnv
            Compare-Object -ReferenceObject $before -DifferenceObject $after | Should -BeNullOrEmpty
            $after | Should -Contain $guardVariableA
            $after | Should -Contain $guardVariableB
        }
    }

    Context "-WhatIf" {
        It "Reports without removing anything" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = $whatIfVariable
                WhatIf      = $true
            }
            $whatIfResult = @(Remove-DbaSsisEnvironmentVariable @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $whatIfVariable).Count | Should -Be 1
        }
    }

    Context "A variable name that lives in more than one environment" {
        It "Names the environments and removes none of them" {
            # The catalog key is folder plus environment plus variable. Picking one would be a
            # guess and removing both would be a far bigger operation than the caller asked for,
            # so the surviving row in each environment is the assertion, not the message.
            $splatAmbiguous = @{
                SqlInstance     = $ssisInstance
                Variable        = $sharedVariable
                EnableException = $false
                WarningVariable = "ambiguousWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironmentVariable @splatAmbiguous)
            $none.Count | Should -Be 0
            ($ambiguousWarnings -join " ") | Should -BeLike "*exists in more than one environment*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$primaryEnv*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$secondEnv*"
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $sharedVariable).Count | Should -Be 1
            (Get-SsisVariableRow -Folder $secondFolder -Environment $secondEnv -Variable $sharedVariable).Count | Should -Be 1
        }

        It "Throws the same refusal under -EnableException" {
            $splatAmbiguousThrow = @{
                SqlInstance     = $ssisInstance
                Variable        = $sharedVariable
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisEnvironmentVariable @splatAmbiguousThrow } | Should -Throw "*exists in more than one environment*"
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $sharedVariable).Count | Should -Be 1
        }

        It "Removes only the copy in the environment that was named" {
            # Same ambiguous name, disambiguated: the twin in the other environment is what proves
            # the key scoped the removal rather than the command picking the first match.
            $splatScoped = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = $twinVariable
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisEnvironmentVariable @splatScoped)
            $removed.Count | Should -Be 1
            $removed[0].Environment | Should -Be $primaryEnv
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $twinVariable).Count | Should -Be 0
            (Get-SsisVariableRow -Folder $secondFolder -Environment $secondEnv -Variable $twinVariable).Count | Should -Be 1
        }
    }

    Context "Two records in one pipeline" {
        It "Removes the second piped variable as well as the first" {
            # Removal streams per record, so what record 2 does is decided entirely on the second
            # record - record 1 alone proves none of it. The objects come from
            # New-DbaSsisEnvironmentVariable rather than the Get-, because the Get- goes through
            # the Integration Services object model and refuses to run on PowerShell Core; this
            # composition is the same carriage and runs on both editions.
            $splatPipeFixture = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Environment = $primaryEnv
                Variable    = @($pipeVariableA, $pipeVariableB)
                DataType    = "String"
                Value       = "fixture"
            }
            $created = @(New-DbaSsisEnvironmentVariable @splatPipeFixture)
            $created.Count | Should -Be 2

            $removed = @($created[0], $created[1] | Remove-DbaSsisEnvironmentVariable -Confirm:$false)
            $removed.Count | Should -Be 2
            $removed.Name | Should -Contain $pipeVariableA
            $removed.Name | Should -Contain $pipeVariableB
            @($removed | Where-Object Status -NE "Dropped").Count | Should -Be 0
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $pipeVariableA).Count | Should -Be 0
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $pipeVariableB).Count | Should -Be 0
        }
    }

    Context "-InputObject" {
        It "Refuses an object that does not carry the full catalog key" {
            # The variable family emits an undecorated PSObject, so carriage is what identifies
            # one: an object missing Folder and Environment cannot address a variable at all.
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Name        = $guardVariableA
            }
            $splatImposter = @{
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $refused = @($imposter | Remove-DbaSsisEnvironmentVariable @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*must carry SqlInstance, Folder, Environment and Name*"
            (Get-SsisVariableRow -Folder $primaryFolder -Environment $primaryEnv -Variable $guardVariableA).Count | Should -Be 1
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Variable        = $guardVariableA
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisEnvironmentVariable @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Variable        = $guardVariableA
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisEnvironmentVariable @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
