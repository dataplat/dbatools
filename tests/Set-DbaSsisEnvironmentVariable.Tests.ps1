#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSsisEnvironmentVariable",
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
                "Value",
                "SecureValue",
                "Description",
                "DataType",
                "NewName",
                "Sensitive",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should alias Variable to Name" {
            (Get-Command $CommandName).Parameters["Variable"].Aliases | Should -Contain "Name"
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
            $unreachableInstance = "dbatoolsci_nosuchhost_ssisvariable"
        }

        It "Refuses a call that changes nothing" {
            $splatNoChange = @{
                SqlInstance     = $unreachableInstance
                Folder          = "anything"
                Environment     = "anything"
                Variable        = "anything"
                EnableException = $true
            }
            { Set-DbaSsisEnvironmentVariable @splatNoChange } | Should -Throw "*at least one of -Value, -SecureValue, -Description, -DataType, -NewName or -Sensitive*"
        }

        It "Refuses -Value and -SecureValue together" {
            # A secret must never be reachable through the plain parameter, so this settles before
            # a connection is opened rather than after the value has travelled.
            $splatBothValues = @{
                SqlInstance     = $unreachableInstance
                Folder          = "anything"
                Environment     = "anything"
                Variable        = "anything"
                Value           = "plain"
                SecureValue     = (ConvertTo-SecureString -String "secret" -AsPlainText -Force)
                EnableException = $true
            }
            { Set-DbaSsisEnvironmentVariable @splatBothValues } | Should -Throw "*either -Value or -SecureValue, not both*"
        }

        It "Refuses a call with no instance and no input object" {
            { Set-DbaSsisEnvironmentVariable -Description "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses -SqlInstance with no selector at all" {
            # Without one the selection would be every variable in the catalog.
            $splatNoSelector = @{
                SqlInstance     = $unreachableInstance
                Description     = "anything"
                EnableException = $true
            }
            { Set-DbaSsisEnvironmentVariable @splatNoSelector } | Should -Throw "*You must supply -Folder, -Environment or -Variable when connecting with -SqlInstance*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        $variableFolder = "dbatoolsci_setvarfolder1"
        $firstEnvironment = "dbatoolsci_setvarenv1"
        $secondEnvironment = "dbatoolsci_setvarenv2"

        $valueVariable = "dbatoolsci_var_value"
        $descriptionVariable = "dbatoolsci_var_desc"
        $typeVariable = "dbatoolsci_var_type"
        $lossyTypeVariable = "dbatoolsci_var_typelossy"
        $renameVariable = "dbatoolsci_var_rename"
        $renamedVariable = "dbatoolsci_var_rename_after"
        $sensitiveVariable = "dbatoolsci_var_sensitive"
        $promoteVariable = "dbatoolsci_var_promote"
        $firstPipedVariable = "dbatoolsci_var_pipe1"
        $secondPipedVariable = "dbatoolsci_var_pipe2"
        $whatIfVariable = "dbatoolsci_var_whatif"
        $namedVariable = "dbatoolsci_var_named"
        $sharedVariable = "dbatoolsci_var_shared"

        function Get-SsisVariableRow {
            param($EnvironmentName, $VariableName)
            $splatVariableRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT variables.variable_id, variables.name, variables.description, variables.type, variables.sensitive, variables.value, variables.sensitive_value FROM [internal].[environment_variables] variables JOIN [catalog].[environments] environments ON environments.environment_id = variables.environment_id JOIN [catalog].[folders] folders ON folders.folder_id = environments.folder_id WHERE folders.name = @folderName AND environments.name = @environmentName AND variables.name = @variableName"
                SqlParameter = @{ folderName = $variableFolder; environmentName = $EnvironmentName; variableName = $VariableName }
            }
            Invoke-DbaQuery @splatVariableRead
        }

        # SMO and the catalog view both hide a sensitive value; the only way to prove one actually
        # landed is to decrypt it through the environment's own symmetric key, which is what the
        # read command does too.
        function Get-SsisDecryptedValue {
            param($EnvironmentName, $VariableName)
            $decryptQuery = @"
DECLARE @environmentId bigint = (SELECT environments.environment_id FROM [catalog].[environments] environments JOIN [catalog].[folders] folders ON folders.folder_id = environments.folder_id WHERE folders.name = @folderName AND environments.name = @environmentName);
DECLARE @keyName sysname = N'MS_Enckey_Env_' + CONVERT(varchar(20), @environmentId);
DECLARE @certificateName sysname = N'MS_Cert_Env_' + CONVERT(varchar(20), @environmentId);
DECLARE @statement nvarchar(max) = N'OPEN SYMMETRIC KEY ' + QUOTENAME(@keyName) + N' DECRYPTION BY CERTIFICATE ' + QUOTENAME(@certificateName) + N'; SELECT decrypted = CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(sensitive_value)) FROM [internal].[environment_variables] WHERE environment_id = @innerEnvironmentId AND name = @innerVariableName; CLOSE SYMMETRIC KEY ' + QUOTENAME(@keyName) + N';';
EXEC sp_executesql @statement, N'@innerEnvironmentId bigint, @innerVariableName sysname', @innerEnvironmentId = @environmentId, @innerVariableName = @variableName;
"@
            $splatDecrypt = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = $decryptQuery
                SqlParameter = @{ folderName = $variableFolder; environmentName = $EnvironmentName; variableName = $VariableName }
            }
            (Invoke-DbaQuery @splatDecrypt).decrypted
        }

        # Renames make the fixture names at teardown unknowable from here, so the folder is emptied
        # by what it actually holds rather than by the list this file created.
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

        Remove-SsisFolderFixture -FolderName $variableFolder
        $splatNewFolder = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Description = "environment variable set fixture"
        }
        $null = New-DbaSsisFolder @splatNewFolder
        $splatNewEnvironments = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = @($firstEnvironment, $secondEnvironment)
        }
        $null = New-DbaSsisEnvironment @splatNewEnvironments

        $splatStringVariables = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $firstEnvironment
            Variable    = @($descriptionVariable, $renameVariable, $promoteVariable, $firstPipedVariable, $secondPipedVariable, $whatIfVariable, $namedVariable, $sharedVariable)
            Value       = "fixture as created"
            Description = "fixture as created"
        }
        $null = New-DbaSsisEnvironmentVariable @splatStringVariables

        $splatIntVariable = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $firstEnvironment
            Variable    = $valueVariable
            Value       = 1
        }
        $null = New-DbaSsisEnvironmentVariable @splatIntVariable

        # A string that converts to Int32 and one that cannot: the type change re-reads the stored
        # value, so which value is there decides whether the change is possible at all.
        $splatConvertibleVariable = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $firstEnvironment
            Variable    = $typeVariable
            Value       = "5"
        }
        $null = New-DbaSsisEnvironmentVariable @splatConvertibleVariable
        $splatUnconvertibleVariable = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $firstEnvironment
            Variable    = $lossyTypeVariable
            Value       = "not a number"
        }
        $null = New-DbaSsisEnvironmentVariable @splatUnconvertibleVariable

        $splatSensitiveVariable = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $firstEnvironment
            Variable    = $sensitiveVariable
            SecureValue = (ConvertTo-SecureString -String "original secret" -AsPlainText -Force)
            Sensitive   = $true
            DataType    = "String"
        }
        $null = New-DbaSsisEnvironmentVariable @splatSensitiveVariable

        # The same variable name in a second environment: variable names are only unique within an
        # environment, so this is what proves the environment half of the addressing is carried.
        $splatSharedVariable = @{
            SqlInstance = $ssisInstance
            Folder      = $variableFolder
            Environment = $secondEnvironment
            Variable    = $sharedVariable
            Value       = "second environment as created"
        }
        $null = New-DbaSsisEnvironmentVariable @splatSharedVariable
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        Remove-SsisFolderFixture -FolderName $variableFolder
    }

    Context "-Value" {
        It "Sets the value and returns the variable in the create command's shape" {
            $splatSetValue = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $valueVariable
                Value       = 500
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatSetValue)
            $changed.Count | Should -Be 1
            $changed[0].Name | Should -Be $valueVariable
            $changed[0].Value | Should -Be 500
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $valueVariable).value | Should -Be 500

            $splatShapeFixture = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = "dbatoolsci_var_shape"
                Value       = "shape"
            }
            $created = @(New-DbaSsisEnvironmentVariable @splatShapeFixture)[0]
            Compare-Object -ReferenceObject $created.PSObject.Properties.Name -DifferenceObject $changed[0].PSObject.Properties.Name | Should -BeNullOrEmpty
        }

        It "Leaves the same name in another environment alone" {
            # Variable names repeat across environments, so a command that resolves on the name
            # alone would change both copies here and still report one object per selection.
            $splatSharedValue = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $sharedVariable
                Value       = "first environment only"
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatSharedValue)
            $changed.Count | Should -Be 1
            $changed[0].Environment | Should -Be $firstEnvironment
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $sharedVariable).value | Should -Be "first environment only"
            (Get-SsisVariableRow -EnvironmentName $secondEnvironment -VariableName $sharedVariable).value | Should -Be "second environment as created"
        }

        It "Reports a variable that is not there and changes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = "dbatoolsci_var_absent"
                Value           = "should not land"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisEnvironmentVariable @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Reports without changing anything under -WhatIf" {
            $before = (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $whatIfVariable)
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $whatIfVariable
                Value       = "not applied"
                Description = "not applied either"
                WhatIf      = $true
            }
            $whatIfResult = @(Set-DbaSsisEnvironmentVariable @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            $after = (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $whatIfVariable)
            $after.value | Should -Be $before.value
            $after.description | Should -Be $before.description
        }
    }

    Context "-Description" {
        It "Sets the description" {
            $splatDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $descriptionVariable
                Description = "how many rows a batch carries"
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatDescription)
            $changed.Count | Should -Be 1
            $changed[0].Description | Should -Be "how many rows a batch carries"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $descriptionVariable).description | Should -Be "how many rows a batch carries"
        }

        It "Clears the description when given an empty string" {
            # An empty -Description is a value, not an omission. A command testing the string for
            # emptiness instead of testing bound-parameter presence leaves the old text in place
            # and reports success, which is the trap this leg exists for.
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $descriptionVariable).description | Should -Not -BeNullOrEmpty
            $splatClearDescription = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $descriptionVariable
                Description = ""
            }
            $cleared = @(Set-DbaSsisEnvironmentVariable @splatClearDescription)
            $cleared.Count | Should -Be 1
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $descriptionVariable).description | Should -Be ""
        }
    }

    Context "-DataType" {
        It "Converts the variable and then takes the new value" {
            # The type change is applied before the value, so it converts what is already stored -
            # the leg only passes when "5" survives the trip to Int32.
            $splatConvert = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $typeVariable
                DataType    = "Int32"
                Value       = 7
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatConvert)
            $changed.Count | Should -Be 1
            $changed[0].Type | Should -Be "Int32"
            $changed[0].Value | Should -Be 7
            $row = Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $typeVariable
            $row.type | Should -Be "Int32"
            $row.value | Should -Be 7
        }

        It "Warns that a lone type change destroys the stored value, and it does" {
            # Measured on SSISDB schema 6: internal.convert_value coerces instead of refusing, so
            # "not a number" reaches Int32 as 0 with no error at all. That is why the warning is
            # the only protection the caller gets, and why this leg asserts the 0 rather than a
            # failure - an assertion that the call failed would be asserting something untrue.
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $lossyTypeVariable).value | Should -Be "not a number"
            $splatLossy = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $lossyTypeVariable
                DataType        = "Int32"
                WarningVariable = "convertWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatLossy)
            $changed.Count | Should -Be 1
            $changed[0].Type | Should -Be "Int32"
            $changed[0].Value | Should -Be 0
            ($convertWarnings -join " ") | Should -BeLike "*from String to Int32*"
            $row = Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $lossyTypeVariable
            $row.type | Should -Be "Int32"
            $row.value | Should -Be 0
        }

        It "Stays quiet when the new value comes with the new type" {
            $splatQuiet = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $typeVariable
                DataType        = "String"
                Value           = "back to text"
                WarningVariable = "quietWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatQuiet)
            $changed.Count | Should -Be 1
            $changed[0].Value | Should -Be "back to text"
            # Measure-Object rather than @().Count: an unset WarningVariable is $null, and
            # @($null).Count is 1, which would pass a broken assertion here.
            ($quietWarnings | Measure-Object).Count | Should -Be 0
        }
    }

    Context "-Sensitive" {
        It "Promotes a plain variable and stores the new value encrypted" {
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $promoteVariable).sensitive | Should -Be $false
            $splatPromote = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $promoteVariable
                SecureValue = (ConvertTo-SecureString -String "promoted secret" -AsPlainText -Force)
                Sensitive   = $true
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatPromote)
            $changed.Count | Should -Be 1
            $changed[0].IsSensitive | Should -Be $true
            # Null in the plaintext column is the masking: the value the caller gets back is the
            # stored one, and for a sensitive variable the catalog does not store it in the clear.
            $changed[0].Value | Should -BeNullOrEmpty

            $row = Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $promoteVariable
            $row.sensitive | Should -Be $true
            # DBNull, not $null - a DataRow column hands back [DBNull]::Value, which is neither
            # null nor empty to Should -BeNullOrEmpty.
            $row.value -is [System.DBNull] | Should -BeTrue
            # Decrypting is what proves the promotion ran BEFORE the value was written: the flag
            # alone would be identical if the new value had been stored in the clear first.
            Get-SsisDecryptedValue -EnvironmentName $firstEnvironment -VariableName $promoteVariable | Should -Be "promoted secret"
        }

        It "Replaces the value of an already sensitive variable" {
            $splatReplaceSecret = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $sensitiveVariable
                SecureValue = (ConvertTo-SecureString -String "rotated secret" -AsPlainText -Force)
            }
            $changed = @(Set-DbaSsisEnvironmentVariable @splatReplaceSecret)
            $changed.Count | Should -Be 1
            Get-SsisDecryptedValue -EnvironmentName $firstEnvironment -VariableName $sensitiveVariable | Should -Be "rotated secret"
        }

        It "Refuses -Sensitive:`$false against a sensitive variable and leaves it sensitive" {
            # The catalog raises 27116 for this and there is no way back, so the command says what
            # to do instead of passing the raw error on.
            $splatDemote = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $sensitiveVariable
                Sensitive       = $false
                EnableException = $false
                WarningVariable = "demoteWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @(Set-DbaSsisEnvironmentVariable @splatDemote)
            $refused.Count | Should -Be 0
            ($demoteWarnings -join " ") | Should -BeLike "*cannot make it plain again*"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $sensitiveVariable).sensitive | Should -Be $true
        }

        It "Refuses -Value against a sensitive variable and leaves the secret intact" {
            $splatPlainValue = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $sensitiveVariable
                Value           = "leaked in the clear"
                EnableException = $false
                WarningVariable = "plainWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @(Set-DbaSsisEnvironmentVariable @splatPlainValue)
            $refused.Count | Should -Be 0
            ($plainWarnings -join " ") | Should -BeLike "*supply its value with -SecureValue*"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $sensitiveVariable).value -is [System.DBNull] | Should -BeTrue
            Get-SsisDecryptedValue -EnvironmentName $firstEnvironment -VariableName $sensitiveVariable | Should -Be "rotated secret"
        }

        It "Refuses -SecureValue against a variable that stays plain" {
            $splatSecureOnPlain = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $namedVariable
                SecureValue     = (ConvertTo-SecureString -String "false assurance" -AsPlainText -Force)
                EnableException = $false
                WarningVariable = "secureWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @(Set-DbaSsisEnvironmentVariable @splatSecureOnPlain)
            $refused.Count | Should -Be 0
            ($secureWarnings -join " ") | Should -BeLike "*-SecureValue needs -Sensitive*"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $namedVariable).value | Should -Be "fixture as created"
        }
    }

    Context "-NewName" {
        It "Renames a variable piped in from the create command's shape" {
            $piped = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $renameVariable
            }
            $renamed = @($piped | Set-DbaSsisEnvironmentVariable -NewName $renamedVariable)
            $renamed.Count | Should -Be 1
            $renamed[0].Name | Should -Be $renamedVariable
            @(Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $renamedVariable).Count | Should -Be 1
            @(Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $renameVariable).Count | Should -Be 0
        }

        It "Refuses to rename a selection of more than one variable and changes neither" {
            # The count that decides this is the count across the whole pipeline, so a per-record
            # check would have renamed the first variable before the second arrived to refuse it.
            # Two objects are piped literally rather than through a name list, so the leg cannot
            # quietly become a one-record leg if a fixture goes missing.
            $firstObject = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $firstPipedVariable
            }
            $secondObject = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $secondPipedVariable
            }
            $splatBoth = @{
                NewName         = "dbatoolsci_var_collapsed"
                EnableException = $false
                WarningVariable = "collapseWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($firstObject, $secondObject | Set-DbaSsisEnvironmentVariable @splatBoth)
            $refused.Count | Should -Be 0
            ($collapseWarnings -join " ") | Should -BeLike "*-NewName renames one variable*"
            @(Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $firstPipedVariable).Count | Should -Be 1
            @(Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $secondPipedVariable).Count | Should -Be 1
            @(Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName "dbatoolsci_var_collapsed").Count | Should -Be 0
        }
    }

    Context "Two records in one pipeline" {
        It "Changes the second piped variable as well as the first" {
            # A description change streams per record, so what record 2 does is decided entirely
            # on the second record - record 1 alone proves none of it.
            $firstObject = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $firstPipedVariable
            }
            $secondObject = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $secondPipedVariable
            }
            $changed = @($firstObject, $secondObject | Set-DbaSsisEnvironmentVariable -Description "piped in a batch")
            $changed.Count | Should -Be 2
            $changed.Name | Should -Contain $firstPipedVariable
            $changed.Name | Should -Contain $secondPipedVariable
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $firstPipedVariable).description | Should -Be "piped in a batch"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $secondPipedVariable).description | Should -Be "piped in a batch"
        }
    }

    Context "-InputObject" {
        It "Refuses an object that does not carry a variable address" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Name        = $firstPipedVariable
            }
            $splatImposter = @{
                Description     = "should not land"
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @($imposter | Set-DbaSsisEnvironmentVariable @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*must carry SqlInstance, Folder, Environment and Name*"
            (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $firstPipedVariable).description | Should -Be "piped in a batch"
        }
    }

    Context "-SqlInstance named while records are also piped in" {
        It "Acts on the named variable once, not once per piped record" {
            # -SqlInstance is not pipeline-bound: it is supplied once no matter how many records
            # arrive, so the variables it names are one selection, not one per record. Expanded on
            # every record instead, the named variable is updated and emitted as many times as
            # records were piped - which reads as success and quietly does the work twice.
            $firstPiped = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $firstPipedVariable
            }
            $secondPiped = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Name        = $secondPipedVariable
            }
            $splatMixed = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $firstEnvironment
                Variable    = $namedVariable
                Description = "named and piped together"
            }
            $mixed = @($firstPiped, $secondPiped | Set-DbaSsisEnvironmentVariable @splatMixed)

            $mixed.Count | Should -Be 3
            @($mixed | Where-Object Name -EQ $namedVariable).Count | Should -Be 1
            foreach ($touched in @($firstPipedVariable, $secondPipedVariable, $namedVariable)) {
                (Get-SsisVariableRow -EnvironmentName $firstEnvironment -VariableName $touched).description | Should -Be "named and piped together"
            }
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $variableFolder
                Environment     = $firstEnvironment
                Variable        = $namedVariable
                Description     = "no catalog here"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisEnvironmentVariable @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }
    }
}
