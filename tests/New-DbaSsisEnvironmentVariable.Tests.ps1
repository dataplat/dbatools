#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSsisEnvironmentVariable",
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
                "DataType",
                "Value",
                "SecureValue",
                "Sensitive",
                "Description",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Variable" {
            (Get-Command $CommandName).Parameters["Variable"].Aliases | Should -Contain "Name"
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should take one environment and several variables" {
            (Get-Command $CommandName).Parameters["Environment"].ParameterType.FullName | Should -Be "System.String"
            (Get-Command $CommandName).Parameters["Variable"].ParameterType.FullName | Should -Be "System.String[]"
        }

        It "Should take the sensitive value only as a SecureString" {
            # A password bound to an ordinary string parameter survives in the caller's history and
            # in any transcript, so there is deliberately no plain-text route to a sensitive value.
            (Get-Command $CommandName).Parameters["SecureValue"].ParameterType.FullName | Should -Be "System.Security.SecureString"
            (Get-Command $CommandName).Parameters["Sensitive"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
        }
    }

    Context "Value arguments are settled before anything connects" {
        # These all refuse in BeginProcessing, so an unreachable instance name is never dialled -
        # which is the point: the mistake is the caller's, and a secret passed the wrong way has
        # already leaked by the time a connection would have been opened.
        BeforeAll {
            $unreachableInstance = "dbatoolsci_nosuchhost_ssisvar"
            $secretValue = ConvertTo-SecureString -String "dbatoolsci_secret" -AsPlainText -Force
        }

        It "Refuses both -Value and -SecureValue" {
            $splatBoth = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                Value           = "plain"
                SecureValue     = $secretValue
                Sensitive       = $true
                DataType        = "String"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatBoth } | Should -Throw "*either -Value or -SecureValue, not both*"
        }

        It "Refuses neither -Value nor -SecureValue" {
            $splatNeither = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatNeither } | Should -Throw "*must supply either -Value or -SecureValue*"
        }

        It "Refuses -Sensitive without -SecureValue" {
            $splatSensitivePlain = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                Value           = "plain"
                Sensitive       = $true
                DataType        = "String"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatSensitivePlain } | Should -Throw "*never accepted as plain text*"
        }

        It "Refuses -SecureValue without -Sensitive" {
            $splatSecureClear = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                SecureValue     = $secretValue
                DataType        = "String"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatSecureClear } | Should -Throw "*-SecureValue requires -Sensitive*"
        }

        It "Refuses -Sensitive without -DataType" {
            $splatSensitiveUntyped = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                SecureValue     = $secretValue
                Sensitive       = $true
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatSensitiveUntyped } | Should -Throw "*-Sensitive requires -DataType*"
        }

        It "Refuses a value whose type maps to no SSIS type when -DataType is omitted" {
            $splatUnmappable = @{
                SqlInstance     = $unreachableInstance
                Folder          = "dbatoolsci_varfolder1"
                Environment     = "dbatoolsci_varenv1"
                Variable        = "dbatoolsci_var1"
                Value           = [guid]"00000000-0000-0000-0000-0000000000ff"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatUnmappable } | Should -Throw "*Cannot derive an SSIS data type from System.Guid*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance      = $TestConfig.InstanceSsis
        $variableFolder    = "dbatoolsci_varfolder1"
        $variableEnvironment = "dbatoolsci_varenv1"
        $derivedVariable   = "dbatoolsci_var1"
        $typedVariable     = "dbatoolsci_var2"
        $stringVariable    = "dbatoolsci_var3"
        $sensitiveVariable = "dbatoolsci_var4"
        $whatIfVariable    = "dbatoolsci_var5"
        $existingVariable  = "dbatoolsci_var6"
        $survivorVariable  = "dbatoolsci_var7"
        $multiFirstVariable  = "dbatoolsci_var8"
        $multiSecondVariable = "dbatoolsci_var9"
        $aliasVariable     = "dbatoolsci_var10"
        $badTypeVariable   = "dbatoolsci_var11"
        $variableComment   = "dbatools variable create fixture"
        $sensitiveText     = "dbatoolsci_P@ssw0rd_sensitive"

        function Get-SsisVariableRow {
            param($Folder, $Environment, $Variable)
            $splatVariableRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                # base_data_type exists only on the internal table; the catalog view stops at value.
                Query        = "SELECT v.variable_id, v.name, v.description, v.type, v.sensitive, v.value, v.base_data_type FROM [internal].[environment_variables] v JOIN [catalog].[environments] e ON e.environment_id = v.environment_id JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment AND v.name = @variable"
                SqlParameter = @{ folder = $Folder; environment = $Environment; variable = $Variable }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatVariableRead)
        }

        function Get-SsisSensitiveValue {
            param($Folder, $Environment, $Variable)
            # catalog.environment_variables leaves value NULL for a sensitive variable and keeps the
            # ciphertext in internal.environment_variables, so reading it back needs the
            # environment's own symmetric key - the same route Get-DbaSsisEnvironmentVariable takes.
            # The key name is part of an OPEN SYMMETRIC KEY statement and cannot be parameterized,
            # so the id is read first and interpolated.
            $splatEnvironmentId = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT e.environment_id FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment"
                SqlParameter = @{ folder = $Folder; environment = $Environment }
            }
            $environmentId = (Invoke-DbaQuery @splatEnvironmentId).environment_id

            $splatDecrypt = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "OPEN SYMMETRIC KEY MS_Enckey_Env_$environmentId DECRYPTION BY CERTIFICATE MS_Cert_Env_$environmentId; SELECT decrypted = CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(v.sensitive_value)) FROM [internal].[environment_variables] v WHERE v.environment_id = $environmentId AND v.name = @variable; CLOSE SYMMETRIC KEY MS_Enckey_Env_$environmentId;"
                SqlParameter = @{ variable = $Variable }
            }
            (Invoke-DbaQuery @splatDecrypt).decrypted
        }

        $splatFolderSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;"
            SqlParameter = @{ folder = $variableFolder }
        }
        Invoke-DbaQuery @splatFolderSetup

        # A leftover environment from an interrupted run would carry leftover variables with it, so
        # the whole environment is dropped and rebuilt rather than cleaned variable by variable.
        $splatStaleEnvironment = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;"
            SqlParameter = @{ folder = $variableFolder; environment = $variableEnvironment }
        }
        Invoke-DbaQuery @splatStaleEnvironment

        $splatEnvironmentSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "EXEC [catalog].[create_environment] @folder_name = @folder, @environment_name = @environment, @environment_description = NULL;"
            SqlParameter = @{ folder = $variableFolder; environment = $variableEnvironment }
        }
        Invoke-DbaQuery @splatEnvironmentSetup

        $splatExistingVariable = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "EXEC [catalog].[create_environment_variable] @folder_name = @folder, @environment_name = @environment, @variable_name = @variable, @data_type = N'Int32', @sensitive = 0, @value = 1, @description = NULL;"
            SqlParameter = @{ folder = $variableFolder; environment = $variableEnvironment; variable = $existingVariable }
        }
        Invoke-DbaQuery @splatExistingVariable
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $splatEnvironmentCleanup = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;"
            SqlParameter = @{ folder = "dbatoolsci_varfolder1"; environment = "dbatoolsci_varenv1" }
        }
        Invoke-DbaQuery @splatEnvironmentCleanup

        $splatFolderCleanup = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
            SqlParameter = @{ folder = "dbatoolsci_varfolder1" }
        }
        Invoke-DbaQuery @splatFolderCleanup
    }

    Context "Creating a variable" {
        It "Creates the variable and returns it" {
            $splatCreate = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = $derivedVariable
                Value       = 500
                Description = $variableComment
            }
            $created = @(New-DbaSsisEnvironmentVariable @splatCreate)
            $created.Count | Should -Be 1
            $created[0].Name | Should -Be $derivedVariable
            $created[0].Folder | Should -Be $variableFolder
            $created[0].Environment | Should -Be $variableEnvironment
            $created[0].Description | Should -Be $variableComment
            $created[0].Value | Should -Be 500
            $created[0].IsSensitive | Should -Be $false

            $catalogRow = Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $derivedVariable
            $catalogRow.Count | Should -Be 1
            $created[0].Id | Should -Be $catalogRow[0].variable_id
            $catalogRow[0].value | Should -Be 500
        }

        It "Derives the SSIS type from the value when -DataType is omitted" {
            $catalogRow = Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $derivedVariable
            $catalogRow[0].type | Should -Be "Int32"
        }

        It "Passes -DataType through instead of inferring it from the value" {
            # 2.5 is a Double, so a command that inferred the type from the value would record
            # Double here. The declared type is what the SSIS parameter binds against, and Decimal
            # and Double are not interchangeable there, so the caller's word has to win.
            $splatTyped = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = $typedVariable
                Value       = 2.5
                DataType    = "Decimal"
            }
            $typed = @(New-DbaSsisEnvironmentVariable @splatTyped)
            $typed.Count | Should -Be 1
            $typed[0].Type | Should -Be "Decimal"
            (Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $typedVariable)[0].type | Should -Be "Decimal"
        }

        It "Creates a string variable" {
            $splatString = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = $stringVariable
                Value       = "dbatoolsci_stringvalue"
            }
            $stringResult = @(New-DbaSsisEnvironmentVariable @splatString)
            $stringResult.Count | Should -Be 1
            $stringResult[0].Type | Should -Be "String"
            $stringResult[0].BaseDataType | Should -Be "nvarchar"
            $stringResult[0].Value | Should -Be "dbatoolsci_stringvalue"
        }

        It "Creates several variables in one call" {
            $splatMulti = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = @($multiFirstVariable, $multiSecondVariable)
                Value       = $true
            }
            $both = @(New-DbaSsisEnvironmentVariable @splatMulti)
            $both.Count | Should -Be 2
            $both.Name | Should -Contain $multiFirstVariable
            $both.Name | Should -Contain $multiSecondVariable
            $both[0].Type | Should -Be "Boolean"
        }

        It "Binds -Name as an alias of -Variable" {
            $splatAlias = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Name        = $aliasVariable
                Value       = 7
            }
            $viaAlias = @(New-DbaSsisEnvironmentVariable @splatAlias)
            $viaAlias.Count | Should -Be 1
            $viaAlias[0].Name | Should -Be $aliasVariable
        }

        It "Emits the shape the read command emits" {
            # Get-DbaSsisEnvironmentVariable walks the IntegrationServices object model and so runs
            # on Windows PowerShell only; the shape it emits is asserted as a literal list rather
            # than by comparing against a live call, which would compare against nothing on Core.
            $splatShape = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = "dbatoolsci_var12"
                Value       = 1
            }
            $newObject = @(New-DbaSsisEnvironmentVariable @splatShape)[0]
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Folder", "Environment", "Id", "Name", "Description", "Type", "IsSensitive", "BaseDataType", "Value")
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $newObject.PSObject.Properties.Name | Should -BeNullOrEmpty
        }
    }

    Context "A sensitive variable" {
        It "Stores the SecureString encrypted and does not echo it back" {
            $splatSensitive = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = $sensitiveVariable
                SecureValue = (ConvertTo-SecureString -String $sensitiveText -AsPlainText -Force)
                Sensitive   = $true
                DataType    = "String"
            }
            $sensitiveResult = @(New-DbaSsisEnvironmentVariable @splatSensitive)
            $sensitiveResult.Count | Should -Be 1
            $sensitiveResult[0].IsSensitive | Should -Be $true
            # The catalog view leaves value NULL for a sensitive variable, so the secret is never
            # echoed back to the caller without that having to be special-cased in the command.
            $sensitiveResult[0].Value | Should -BeNullOrEmpty

            $catalogRow = Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $sensitiveVariable
            $catalogRow.Count | Should -Be 1
            $catalogRow[0].sensitive | Should -Be $true
            $catalogRow[0].value | Should -BeNullOrEmpty
        }

        It "Round-trips the secret through the SecureString unchanged" {
            # The value is copied out of the SecureString into a char array bound straight to the
            # SqlParameter and never becomes a managed string, so this leg is what proves the
            # marshalling did not truncate or mangle it on the way to the server.
            Get-SsisSensitiveValue -Folder $variableFolder -Environment $variableEnvironment -Variable $sensitiveVariable | Should -Be $sensitiveText
        }
    }

    Context "-WhatIf" {
        It "Reports without creating the variable" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = $variableEnvironment
                Variable    = $whatIfVariable
                Value       = 1
                WhatIf      = $true
            }
            $whatIfResult = @(New-DbaSsisEnvironmentVariable @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $whatIfVariable).Count | Should -Be 0
        }
    }

    Context "Each variable succeeds or fails on its own" {
        It "Errors on the name that already exists and still creates the rest" {
            # Without -EnableException the failure surfaces as the friendly warning, not an error
            # record, so -ErrorVariable would come back empty and prove nothing.
            $splatMixed = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $variableEnvironment
                Variable        = @($existingVariable, $survivorVariable)
                Value           = 2
                EnableException = $false
                WarningVariable = "variableWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $mixed = @(New-DbaSsisEnvironmentVariable @splatMixed)
            $mixed.Count | Should -Be 1
            $mixed[0].Name | Should -Be $survivorVariable
            ($variableWarnings -join " ") | Should -BeLike "*$existingVariable*"
            (Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $existingVariable)[0].value | Should -Be 1
        }
    }

    Context "A data type the catalog does not accept" {
        It "Lets the server refuse it rather than accepting it silently" {
            # The catalog validates -DataType against internal.data_type_mapping, and varchar is
            # not among the base types it allows for String - so a passed-through type is checked
            # by the one component that knows the domain.
            $splatBadType = @{
                SqlInstance     = $ssisInstance
                Folder          = $variableFolder
                Environment     = $variableEnvironment
                Variable        = $badTypeVariable
                Value           = "dbatoolsci_badtype"
                DataType        = "Varchar"
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatBadType } | Should -Throw
            (Get-SsisVariableRow -Folder $variableFolder -Environment $variableEnvironment -Variable $badTypeVariable).Count | Should -Be 0
        }
    }

    Context "An environment that does not exist" {
        It "Refuses rather than creating the environment" {
            $splatMissingEnvironment = @{
                SqlInstance = $ssisInstance
                Folder      = $variableFolder
                Environment = "dbatoolsci_varnosuchenv"
                Variable    = "dbatoolsci_varorphan"
                Value       = 1
            }
            { New-DbaSsisEnvironmentVariable @splatMissingEnvironment } | Should -Throw "*dbatoolsci_varnosuchenv*"

            $splatEnvironmentCheck = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS environments FROM [catalog].[environments] WHERE name = @environment"
                SqlParameter = @{ environment = "dbatoolsci_varnosuchenv" }
            }
            (Invoke-DbaQuery @splatEnvironmentCheck).environments | Should -Be 0
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $variableFolder
                Environment     = $variableEnvironment
                Variable        = "dbatoolsci_varnocatalog"
                Value           = 1
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(New-DbaSsisEnvironmentVariable @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $variableFolder
                Environment     = $variableEnvironment
                Variable        = "dbatoolsci_varnocatalog"
                Value           = 1
                EnableException = $true
            }
            { New-DbaSsisEnvironmentVariable @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
